import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/notification_service.dart';

/// Screen mit den wichtigsten Regeln für die Dating Hour.
///
/// Wird beim ersten Betreten der Dating Hour angezeigt, damit Nutzer
/// die Erwartungen und Verbotsregeln direkt sehen.
class DatingHourRulesScreen extends ConsumerWidget {
  const DatingHourRulesScreen({super.key});

  static const _rules = <_RuleItem>[
    _RuleItem(
      'Respektvoll bleiben',
      'Behandele deinen Gegenüber mit Respekt. Keine Beleidigungen, '
      'Diskriminierung oder unerwünschte Nachrichten.',
    ),
    _RuleItem(
      'Keine persönlichen Daten teilen',
      'Gib keine Adressen, Telefonnummern oder Kontodetails preis. '
      'Bleibt zunächst in der App.',
    ),
    _RuleItem(
      'Ehrliches Profil',
      'Nutze nur echte Angaben und aktuelle Bilder. Fake Profile oder '
      'Identitätsdiebstahl werden gemeldet.',
    ),
    _RuleItem(
      '5 Minuten Regel',
      'Jeder Chat dauert maximal 5 Minuten. Danach entscheidest du, ob '
      'du das Match verlängern möchtest.',
    ),
    _RuleItem(
      'Keine unerwünschten Bilder',
      'Sende keine intimen Bilder oder unerwünschten Content. '
      'Verstöße führen zur sofortigen Sperrung.',
    ),
    _RuleItem(
      'Minderjährigenschutz',
      'Die Dating Hour ist erst ab 16 Jahren freigegeben. '
      'Jüngere Nutzer werden automatisch ausgeschlossen.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dating Hour Regeln'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bitte lies diese Regeln aufmerksam durch, bevor du '
              'an der Dating Hour teilnimmst.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ..._rules.map(
              (rule) => _RuleExpansion(rule: rule),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                NotificationService.instance.show(
                  id: 999,
                  title: 'Regeln akzeptiert',
                  body: 'Viel Spaß bei der Dating Hour!',
                  ref: ref,
                  type: NotificationType.datingHour,
                );
                context.go(AppRoutes.datingHourHowItWorks);
              },
              child: const Text('Weiter'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleExpansion extends StatelessWidget {
  const _RuleExpansion({required this.rule});

  final _RuleItem rule;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        // Keine Trennlinien ober-/unterhalb der Bubble (Default-Zeichnung
        // des ExpansionTile zieht im aufgeklappten Zustand Divider-Linien).
        shape: const Border(),
        title: Text(
          rule.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(rule.body),
          ),
        ],
      ),
    );
  }
}

class _RuleItem {
  const _RuleItem(this.title, this.body);

  final String title;
  final String body;
}
