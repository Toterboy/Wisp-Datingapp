import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/spice_question.dart';
import 'package:wisp/providers/spice_question_provider.dart';
import 'package:wisp/services/spice_question_service.dart';

/// "Spice Questions": Eisbrecher-Fragen für ein Match (Feature A).
///
/// Beide Partner antworten unabhängig; erst wenn beide geantwortet haben,
/// werden die Antworten aufgedeckt (serverseitig erzwungen).
class SpiceQuestionsScreen extends ConsumerStatefulWidget {
  const SpiceQuestionsScreen({required this.matchId, super.key});

  final int matchId;

  @override
  ConsumerState<SpiceQuestionsScreen> createState() =>
      _SpiceQuestionsScreenState();
}

class _SpiceQuestionsScreenState extends ConsumerState<SpiceQuestionsScreen> {
  Future<void> _openAnswerDialog(SpiceQuestion question) async {
    final controller = TextEditingController(
      text: question.myAnswer ?? '',
    );

    final answer = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deine Antwort'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question.prompt,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Schreib deine Antwort⬦',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.of(ctx).pop(text);
            },
            child: const Text('Senden'),
          ),
        ],
      ),
    );

    if (answer == null || answer.isEmpty || !mounted) return;

    final result = await ref
        .read(spiceQuestionServiceProvider)
        .answer(widget.matchId, question.questionId, answer);

    if (!mounted) return;
    ref.invalidate(spiceQuestionsProvider(widget.matchId));

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Antwort konnte nicht gesendet werden.')),
      );
    } else if (result.bothAnswered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Beide haben geantwortet: Antwort aufgedeckt!'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Antwort gesendet. Dein Gegenüber antwortet bald.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(spiceQuestionsProvider(widget.matchId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eisbrecher-Fragen'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: () =>
                ref.invalidate(spiceQuestionsProvider(widget.matchId)),
          ),
        ],
      ),
      body: questionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text('Fragen konnten nicht geladen werden:\n$err',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(spiceQuestionsProvider(widget.matchId)),
                  child: const Text('Erneut versuchen'),
                ),
              ],
            ),
          ),
        ),
        data: (questions) {
          if (questions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine Eisbrecher-Fragen verfügbar. '
                  'Probier es später erneut.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: questions.length,
            itemBuilder: (context, index) =>
                _QuestionCard(
              question: questions[index],
              onAnswer: () => _openAnswerDialog(questions[index]),
            ),
          );
        },
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, required this.onAnswer});

  final SpiceQuestion question;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bothAnswered = question.answeredByBoth;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    question.prompt,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  bothAnswered
                      ? Icons.visibility
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: bothAnswered
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (bothAnswered) ...[
              _AnswerBox(
                label: 'Deine Antwort',
                text: question.myAnswer ?? '(offen)',
                color: theme.colorScheme.primaryContainer,
              ),
              const SizedBox(height: 8),
              _AnswerBox(
                label: 'Antwort von deinem Match',
                text: question.partnerAnswer ?? '(offen)',
                color: theme.colorScheme.tertiaryContainer,
              ),
            ] else if (question.answeredByMe) ...[
              _AnswerBox(
                label: 'Deine Antwort',
                text: question.myAnswer ?? '(offen)',
                color: theme.colorScheme.primaryContainer,
              ),
              const SizedBox(height: 8),
              Text(
                'Warte auf die Antwort deines Matches⬦',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              Text(
                'Deine Antwort wird erst aufgedeckt, wenn dein Gegenüber '
                'ebenfalls geantwortet hat.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: onAnswer,
                child: Text(question.answeredByMe ? 'Antwort ändern' : 'Antworten'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerBox extends StatelessWidget {
  const _AnswerBox({
    required this.label,
    required this.text,
    required this.color,
  });

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(text),
        ],
      ),
    );
  }
}