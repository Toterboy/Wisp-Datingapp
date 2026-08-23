import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:wisp/routing/app_router.dart';

/// Safety Center: zentrale Anlaufstelle bei Belästigung, Stalking oder
/// Bedrohung – mit externen Hilfsangeboten und In-App-Maßnahmen.
///
/// Alle externen Links öffnen bewusst im Systembrowser/Telefon-App
/// (url_launcher); die App selbst übermittelt dabei keine Nutzungsdaten.
class SafetyCenterScreen extends StatelessWidget {
  const SafetyCenterScreen({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konnte Link nicht öffnen.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Center')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.emergency_outlined,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bei akuter Gefahr rufe sofort die Polizei: 110. '
                      'Du bist nicht allein – die folgenden Stellen helfen '
                      'kostenlos und vertraulich.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Sofort Hilfe',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.phone_in_talk),
            title: const Text('Hilfetelefon „Gewalt gegen Frauen“'),
            subtitle: const Text('116 016 · kostenlos, 24/7, anonym'),
            trailing: const Icon(Icons.call),
            onTap: () => _open(context, Uri(scheme: 'tel', path: '116016')),
          ),
          ListTile(
            leading: const Icon(Icons.phone_in_talk),
            title: const Text('TelefonSeelsorge'),
            subtitle:
                const Text('0800 111 0 111 · kostenlos, 24/7'),
            trailing: const Icon(Icons.call),
            onTap: () => _open(context, Uri(scheme: 'tel', path: '08001110111')),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('klicksafe (Cybermobbing & Beratung)'),
            subtitle: const Text('klicksafe.de'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _open(context, Uri.parse('https://www.klicksafe.de')),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Hilfetelefon Stalking (Weisser Ring)'),
            subtitle: const Text('weisser-ring.de · 116 006'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () =>
                _open(context, Uri.parse('https://weisser-ring.de')),
          ),
          const Divider(height: 32),
          Text('Schutz in WispDating',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const ExpansionTile(
            leading: Icon(Icons.flag_outlined),
            title: Text('Jemanden melden'),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Im Chat über das Flag-Symbol oben rechts oder per langem '
                  'Drücken auf ein Bild. Deine letzten Nachrichten werden '
                  'transparent als Kontext übermittelt und vom Support '
                  'persönlich geprüft.',
                ),
              ),
            ],
          ),
          const ExpansionTile(
            leading: Icon(Icons.block_outlined),
            title: Text('Jemanden blockieren'),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Chat-Menü (drei Punkte) → Blockieren. Likes und Match '
                  'werden entfernt; künftige Interaktionen werden serverseitig '
                  'verhindert – die Person erfährt nicht davon.',
                ),
              ),
            ],
          ),
          const ExpansionTile(
            leading: Icon(Icons.lock_person_outlined),
            title: Text('Eigene Bilder schützen'),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Bilder eingehender Nachrichten sind standardmäßig '
                  'verpixelt (Einstellungen → Sicherheit im Chat). Eigene '
                  'Fotos bleiben bis zum gegenseitigen Quiz-Erfolg '
                  'grundsätzlich verborgen.',
                ),
              ),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Meine Daten exportieren'),
            subtitle: const Text('JSON-Export aller gespeicherten Daten'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.privacy),
          ),
          const Divider(height: 32),
          Text('Stalking-Leitfaden',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Wenn dir jemand online (oder offline) nachstellt:\n'
            '1. Nicht antworten – Kontakt bewusst abbrechen.\n'
            '2. Alles dokumentieren: Screenshots mit Datum, Chatverlauf, '
            'Profilnamen.\n'
            '3. In-App blockieren und uns über die Melde-Funktion informieren '
            '– wir können Accounts dauerhaft sperren.\n'
            '4. Passwörter ändern und 2FA aktivieren (Einstellungen).\n'
            '5. Bei Bedrohung oder Angst: Polizei (110) bzw. 116 006 kontaktieren.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
