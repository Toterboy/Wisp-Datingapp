import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/providers/meet_intent_provider.dart';

/// Vorschlag-Karte für ein echtes Treffen im Chat.
///
/// Zustände:
/// - Match zu frisch (< 14 Tage): nichts.
/// - Beide wollen & nicht getroffen: Planungskarte.
/// - Ich will, Partner noch nicht: Warte-Hinweis.
/// - Partner will, ich noch nicht: Zustimmungs-Abfrage.
/// - Noch keiner: sanfter Vorschlag.
/// - Getroffen bestätigt: Erfolgsmeldung.
class MeetIntentCard extends ConsumerStatefulWidget {
  const MeetIntentCard({
    super.key,
    required this.matchId,
    required this.partnerName,
  });

  final String matchId;
  final String partnerName;

  @override
  ConsumerState<MeetIntentCard> createState() => _MeetIntentCardState();
}

class _MeetIntentCardState extends ConsumerState<MeetIntentCard> {
  // "Später" blendet die Karte nur für die aktuelle Sitzung aus.
  bool _dismissed = false;

  // Optionale Planungs-Notiz.
  final _noteCtrl = TextEditingController();

  static const _dateIdeas = [
    'Kaffee trinken',
    'Spazieren gehen',
    'Ins Kino',
    'Museum besuchen',
    'Etwas essen gehen',
  ];

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Lokale Kontakte (QR) haben keine DB-Match-ID -> keine Treffen-Logik.
    if (int.tryParse(widget.matchId) == null) {
      return const SizedBox.shrink();
    }

    final intent = ref.watch(meetIntentProvider(widget.matchId));
    if (intent == null) return const SizedBox.shrink();

    if (intent.metConfirmed) {
      return _card(
        icon: Icons.celebration,
        color: Colors.green,
        title: 'Schön, dass ihr euch getroffen habt! 🎉',
        body: 'Wir hoffen, ihr hattet eine schöne Zeit. '
            'Echte Verbindungen statt nur Online-Reden.',
      );
    }

    if (!intent.eligible) return const SizedBox.shrink();
    if (_dismissed) return const SizedBox.shrink();

    final notifier = ref.read(meetIntentProvider(widget.matchId).notifier);

    if (intent.bothWant) {
      return _planningCard(notifier);
    }

    if (intent.myWants && !intent.partnerWants) {
      return _card(
        icon: Icons.schedule,
        color: Theme.of(context).colorScheme.primary,
        title: 'Du möchtest dich treffen',
        body: 'Wir haben ${widget.partnerName} deinen Wunsch weitergegeben. '
            'Sobald ${widget.partnerName} zustimmt, könnt ihr planen.',
      );
    }

    if (!intent.myWants && intent.partnerWants) {
      return _card(
        icon: Icons.favorite,
        color: Theme.of(context).colorScheme.primary,
        title: '${widget.partnerName} würde sich gerne mit dir treffen',
        body: 'Was hältst du davon, es mal wirklich zu versuchen?',
        actions: [
          FilledButton(
            onPressed: () => notifier.setWants(true),
            child: const Text('Ja, gerne'),
          ),
          TextButton(
            onPressed: () => notifier.setWants(false),
            child: const Text('Doch lieber nicht'),
          ),
        ],
      );
    }

    // Noch keiner will.
    return _card(
      icon: Icons.coffee,
      color: Theme.of(context).colorScheme.primary,
      title: 'Lust auf ein echtes Treffen?',
      body: 'Ihr schreibt euch schon eine Weile – wie wär\'s mit einem '
          'Kaffee oder einem Spaziergang? Trefft euch an einem öffentlichen '
          'Ort.',
      actions: [
        FilledButton(
          onPressed: () => notifier.setWants(true),
          child: const Text('Ja, ich will'),
        ),
        TextButton(
          onPressed: () => setState(() => _dismissed = true),
          child: const Text('Vielleicht später'),
        ),
      ],
    );
  }

  Widget _planningCard(MeetIntentNotifier notifier) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.handshake),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ihr wollt euch treffen! 🎉',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Ideen für ein erstes Treffen:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _dateIdeas
                  .map((idea) => Chip(label: Text(idea)))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Notiz (z. B. "Samstag, 15 Uhr, Café X")',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Wir haben uns getroffen'),
                    onPressed: () => notifier.confirmMet(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Tip: Trifft euch immer an einem öffentlichen Ort und sag einer '
              'Vertrauensperson Bescheid.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    List<Widget> actions = const [],
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: actions
                    .map((a) => [a, const SizedBox(width: 8)])
                    .expand((e) => e)
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
