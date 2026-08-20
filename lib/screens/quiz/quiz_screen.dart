import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/find_match_models.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/find_your_match_service.dart';
import 'package:wisp/services/quiz_service.dart';
import 'package:wisp/widgets/intro_audio_player.dart';

/// Quiz "Wie gut kenn ich mein Match".
///
/// Beide Partner erhalten dieselbe Frage. Bestehen beide, ist das Profilfoto
/// dauerhaft freigeschaltet (Stufe 2, final). Fehlversuche schalten das Foto
/// progressiv frei (0 = unscharf/SW, 1 = scharf/SW) und starten einen
/// serverseitig geprüften 5-Minuten-Cooldown.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({required this.matchId, super.key});

  final int matchId;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  QuizState? _state;
  QuizQuestion? _question;
  QuizAnswerResult? _result;
  int? _selectedIndex;
  bool _loading = true;
  bool _submitting = false;
  String? _avatarUrl;
  String? _error;

  Timer? _cooldownTimer;
  Timer? _waitingTimer;
  int _cooldownLeft = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _waitingTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = ref.read(quizServiceProvider);
    final state = await service.getState(widget.matchId);
    if (!mounted) return;
    if (state == null) {
      setState(() {
        _loading = false;
        _error = 'Quiz-Zustand konnte nicht geladen werden.';
      });
      return;
    }
    setState(() {
      _state = state;
      _loading = false;
    });
    if (state.passed || state.failedAttempts > 0 || state.roundInProgress) {
      _loadAvatar();
    }
    if (!state.passed && state.failedAttempts > 0) {
      _startCooldownTicker();
    }
    if (state.roundInProgress) {
      // Laufende Runde: Habe ich schon geantwortet, warte ich auf den
      // Partner; sonst Frage laden.
      if (state.answeredCurrent) {
        setState(() {
          _result = const QuizAnswerResult(
            correct: true,
            passed: false,
            waitingForPartner: true,
          );
        });
        _startWaitingPoll();
      } else {
        _loadQuestion();
      }
    }
  }

  Future<void> _loadAvatar() async {
    final state = _state;
    if (state == null) return;
    final service = ref.read(findYourMatchServiceProvider);
    final url = await service.getAvatarUrl(state.partnerId);
    if (mounted && url != null) {
      setState(() => _avatarUrl = url);
    }
  }

  void _startCooldownTicker() {
    _cooldownTimer?.cancel();
    final state = _state;
    if (state == null) return;
    void tick() {
      final next = state.nextAttemptAt;
      if (next == null) {
        setState(() => _cooldownLeft = 0);
        return;
      }
      final left = next.difference(DateTime.now()).inSeconds;
      setState(() => _cooldownLeft = left < 0 ? 0 : left);
      if (left <= 0) {
        _cooldownTimer?.cancel();
      }
    }

    tick();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _loadQuestion() async {
    final service = ref.read(quizServiceProvider);
    final question = await service.startAttempt(widget.matchId);
    if (!mounted || question == null) return;
    if (question.prompt == '__cooldown__') {
      setState(() => _result = null);
      await _load();
      return;
    }
    setState(() => _question = question);
  }

  Future<void> _submit() async {
    final question = _question;
    final selected = _selectedIndex;
    if (question == null || selected == null || _submitting) return;
    setState(() => _submitting = true);
    final service = ref.read(quizServiceProvider);
    final result =
        await service.submitAnswer(widget.matchId, question.id, selected);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _result = result;
      _question = null;
      _selectedIndex = null;
    });
    if (result != null) {
      if (result.passed) {
        await _load();
      } else if (result.waitingForPartner) {
        _startWaitingPoll();
      } else {
        await _load();
      }
    }
  }

  /// Pollt, bis der Partner die aktuelle Runde beantwortet hat.
  void _startWaitingPoll() {
    _waitingTimer?.cancel();
    _waitingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final service = ref.read(quizServiceProvider);
      final state = await service.getState(widget.matchId);
      if (!mounted || state == null) return;
      if (state.passed) {
        _waitingTimer?.cancel();
        setState(() => _state = state);
        _loadAvatar();
      } else if (!state.roundInProgress && state.failedAttempts > 0) {
        _waitingTimer?.cancel();
        setState(() {
          _state = state;
          _result = const QuizAnswerResult(
            correct: true,
            passed: false,
            roundClosed: true,
          );
        });
        _startCooldownTicker();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final state = _state;
    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kennenlern-Quiz')),
        body: Center(child: Text(_error ?? 'Unbekannter Fehler')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Kennenlern-Quiz')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.passed)
              _buildPassed(context, state)
            else ...[
              _buildPhoto(context, state),
              const SizedBox(height: 16),
              if (_question != null)
                _buildQuestion(context)
              else if (_result != null)
                _buildResult(context, _result!)
              else if (_cooldownLeft > 0 && state.failedAttempts > 0)
                _buildCooldown(context)
              else
                _buildStart(context),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- Foto-Logik --

  /// Foto-Vorschau gemäß Freischaltungslevel:
  ///   - noch kein Fehlversuch: ausgeblendet
  ///   - Level 0: unscharf + Schwarz-Weiß
  ///   - Level 1: scharf + Schwarz-Weiß
  ///   - Level 2 (bestanden): scharf + farbig (dauerhaft)
  Widget _buildPhoto(BuildContext context, QuizState state) {
    final neverAttempted = state.failedAttempts == 0 && !state.passed;
    if (neverAttempted) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.visibility_off, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('Foto noch verborgen'),
            ],
          ),
        ),
      );
    }

    Widget image = _avatarUrl != null
        ? Image.network(
            _avatarUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.person, size: 96),
          )
        : const Icon(Icons.person, size: 96);

    if (state.unlockLevel < 2) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: state.unlockLevel == 0 ? 12 : 0,
          sigmaY: state.unlockLevel == 0 ? 12 : 0,
        ),
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: image,
        ),
      );
    }

    return Container(
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: image,
    );
  }

  // ------------------------------------------------------------- Zustände --

  Widget _buildStart(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Wie gut kennst du dein Match?',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Ihr bekommt dieselbe Frage. Antwortet ihr beide richtig, ist das '
          'Foto dauerhaft freigeschaltet.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _loadQuestion,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Versuch starten'),
        ),
      ],
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final question = _question!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          question.prompt,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ...List.generate(question.options.length, (i) {
          final selected = _selectedIndex == i;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => setState(() => _selectedIndex = i),
              style: OutlinedButton.styleFrom(
                backgroundColor: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              child: Text(question.options[i]),
            ),
          );
        }),
        const SizedBox(height: 16),
        FilledButton(
          onPressed:
              (_selectedIndex == null || _submitting) ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Antwort abgeben'),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context, QuizAnswerResult result) {
    if (result.passed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.celebration, size: 64, color: Colors.green),
          const SizedBox(height: 8),
          Text(
            'Bestanden! Das Foto ist jetzt dauerhaft freigeschaltet.',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final state = _state;
              context.go(
                AppRoutes.chatDetailPath(widget.matchId.toString()),
              );
              if (state != null && state.partnerId.isNotEmpty) {
                // Partner-Profil ist jetzt voll zugänglich.
              }
            },
            child: const Text('Zum Chat'),
          ),
        ],
      );
    }
    if (result.waitingForPartner) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.hourglass_top, size: 64, color: Colors.orange),
          const SizedBox(height: 8),
          Text(
            'Richtig! Jetzt wartest du auf die Antwort deines Matches.',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Antwortet dein Match auch richtig, ist das Quiz bestanden.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    if (result.roundClosed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.info_outline, size: 48, color: Colors.orange),
          const SizedBox(height: 8),
          Text(
            'Die Runde ist vorbei. Dein Match hat sie nicht bestanden, '
            'also startet ihr nach der Pause gemeinsam neu.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.close, size: 48, color: Colors.red),
        const SizedBox(height: 8),
        Text(
          'Leider falsch.',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Fehlversuch ${result.failedAttempts}: Foto-Stufe ${result.unlockLevel}. '
          'Neuer Versuch nach der 5-Minuten-Pause.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCooldown(BuildContext context) {
    final minutes = (_cooldownLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_cooldownLeft % 60).toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.timer_outlined, size: 64, color: Colors.orange),
        const SizedBox(height: 8),
        Text(
          'Nächster Versuch in $minutes:$seconds',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Nach jedem Fehlversuch gilt eine Pause von 5 Minuten. '
          'Danach könnt ihr es erneut versuchen.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (_cooldownLeft <= 0)
          FilledButton.icon(
            onPressed: () async {
              await _load();
              if (_cooldownLeft <= 0) {
                _loadQuestion();
              }
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Bereit - neuen Versuch starten'),
          ),
      ],
    );
  }

  Widget _buildPassed(BuildContext context, QuizState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPhoto(context, state),
        const SizedBox(height: 16),
        const Icon(Icons.check_circle, size: 48, color: Colors.green),
        const SizedBox(height: 8),
        Text(
          'Quiz bestanden!',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Das Foto bleibt dauerhaft scharf und farbig. Das komplette Profil '
          'deines Matches ist jetzt freigeschaltet.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (state.partnerId.isNotEmpty)
          IntroAudioPlayer(targetUserId: state.partnerId),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () =>
              context.go(AppRoutes.chatDetailPath(widget.matchId.toString())),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Zum Chat'),
        ),
      ],
    );
  }
}
