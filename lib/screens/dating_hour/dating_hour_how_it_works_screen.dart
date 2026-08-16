import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/routing/app_router.dart';
import 'package:wisp/providers/settings_provider.dart';

/// Screen, der erklärt, wie die Dating Hour funktioniert.
///
/// Wird direkt nach den Regeln angezeigt, bevor die eigentliche Event-Seite
/// geöffnet wird.
class DatingHourHowItWorksScreen extends ConsumerWidget {
  const DatingHourHowItWorksScreen({super.key});

  static const _steps = <_HowItWorksItem>[
    _HowItWorksItem(
      'Beitreten',
      'Wähle deine Präferenzen und trete dem täglichen Event bei. '
      'Du kannst jederzeit wieder austreten.',
    ),
    _HowItWorksItem(
      'Warten auf eine Zuordnung',
      'Die App verbindet dich mit einer passenden Person. '
      'Sobald beide bereit sind, startet der 5 Minuten Chat.',
    ),
    _HowItWorksItem(
      '5 Minuten chatten',
      'Lerne die Person in einem kurzen, zeitlich begrenzten Gespräch kennen. '
      'Fotos werden je nach Einstellung angezeigt.',
    ),
    _HowItWorksItem(
      'Entscheidung',
      'Nach dem Gespräch entscheidest du, ob du den Kontakt verlängern '
      'oder beenden möchtest.',
    ),
    _HowItWorksItem(
      'Matches',
      'Wenn beide sich für eine Verlängerung entscheiden, wird ein Match '
      'erstellt und ihr könnt weiter chatten.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wie funktioniert Dating Hour?'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Die Dating Hour läuft jeden Tag von 20:00 bis 21:00 Uhr. '
              'Hier ist der Ablauf im Überblick:',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ..._steps.map(
              (step) => _StepExpansion(step: step),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final settingsNotifier = ref.read(settingsProvider.notifier);
                await settingsNotifier.markDatingHourIntroSeen();
                if (context.mounted) {
                  context.go(AppRoutes.datingHourEvent);
                }
              },
              child: const Text('Zur Dating Hour'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepExpansion extends StatelessWidget {
  const _StepExpansion({required this.step});

  final _HowItWorksItem step;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        // Keine Trennlinien ober-/unterhalb der Bubble.
        shape: const Border(),
        title: Text(
          step.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(step.body),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksItem {
  const _HowItWorksItem(this.title, this.body);

  final String title;
  final String body;
}
