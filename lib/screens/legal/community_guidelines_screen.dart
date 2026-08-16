import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/routing/app_router.dart';

/// Screen mit den Community-Regeln (Netiquette) der App.
class CommunityGuidelinesScreen extends StatelessWidget {
  const CommunityGuidelinesScreen({super.key});

  static const _paragraphs = <_Rule>[
    _Rule(
      '§0 Respektvoller Umgang',
      'Wir erwarten von allen Nutzern einen freundlichen, respektvollen und '
      'wertschätzenden Umgang miteinander, unabhängig von Herkunft, Geschlecht, '
      'sexueller Orientierung, Religion oder Aussehen. Kritik und Ablehnung '
      'sollen stets sachlich und ohne Herabwürdigung erfolgen.',
    ),
    _Rule(
      '§1 Keine Belästigung',
      'Beleidigungen, Diskriminierung, Drohungen oder unerwünschte sexuelle '
      'Ansprachen sind nicht gestattet und führen zum sofortigen Ausschluss.',
    ),
    _Rule(
      '§2 Echte Profile',
      'Nutze nur echte Angaben und Bilder von dir selbst. Fake Profile oder '
      'das Vorgeben einer falschen Identität sind untersagt.',
    ),
    _Rule(
      '§3 Kein Spam',
      'Werbung, Kettenbriefe oder das gezielte Weiterleiten von Links zu '
      'externen Angeboten sind nicht erlaubt.',
    ),
    _Rule(
      '§4 Datenschutz',
      'Teile keine fremden privaten Daten (Adressen, Telefonnummern, Dokumente) '
      'ohne Zustimmung. Achtung auf den Schutz Minderjähriger hat oberste '
      'Priorität.',
    ),
    _Rule(
      '§5 Melden & Konsequenzen',
      'Verstöße können über den Melde Button in Profil und Chat '
      'gemeldet werden. Wiederholter oder schwerer Verstoß führt zur Sperrung '
      'des Accounts.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.settings);
            }
          },
          tooltip: 'Zurück',
        ),
        title: const Text('Community Regeln'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _paragraphs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final rule = _paragraphs[i];
          final isIntro = i == 0;
          return Card(
            color: isIntro
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isIntro
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : null,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rule.body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isIntro
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : null,
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Rule {
  const _Rule(this.title, this.body);
  final String title;
  final String body;
}

