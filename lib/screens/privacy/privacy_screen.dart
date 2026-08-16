import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/routing/app_router.dart';

/// DSGVO-relevanter Datenschutz- und Account-Screen.
///
/// - Zeigt die verarbeiteten Daten an (knappe Übersicht).
/// - Ermöglicht den Export der eigenen Daten (Placeholder; vollständiger
///   Export erfordert eine serverseitige Edge Function).
/// - Ermöglicht das vollständige Löschen des Accounts inkl. aller Daten.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _requestDataExport(BuildContext context, WidgetRef ref) async {
    // TODO: Export über serverseitige Edge Function umsetzen (z. B.
    // `export-account-data`), die Profile, Matches, Messages, Likes, Photos
    // etc. als JSON bereitstellt.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Datenexport ist noch in Vorbereitung. Bitte wende dich an support@wisp.app.',
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Account löschen?'),
        content: const Text(
          'Dieser Schritt kann nicht rückgängig gemacht werden. '
          'Alle deine Daten (Profil, Fotos, Chats, Matches, Likes) '
          'werden dauerhaft gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(authProvider.notifier).deleteAccount();
      if (context.mounted) {
        context.go(AppRoutes.welcome);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account konnte nicht gelöscht werden: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Datenschutz & Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Deine Daten'),
          const _InfoCard(
            text:
                'Wisp speichert Profilinformationen, Standortdaten (nur wenn '
                'du sie freigibst), Fotos, Chats, Likes und Matches. '
                'Alle Daten werden verschlüsselt übertragen und nur so lange '
                'gespeichert, wie dein Account aktiv ist.',
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Meine Daten exportieren'),
            subtitle: const Text('JSON Download aller personenbezogenen Daten'),
            onTap: () => _requestDataExport(context, ref),
          ),
          const Divider(height: 32),
          const _SectionTitle('Einwilligungen'),
          ListTile(
            leading: const Icon(Icons.location_on),
            title: const Text('Standortfreigabe'),
            subtitle: const Text(
                'Du kannst die Standortfreigabe in den Systemeinstellungen '
                'deines Geräts jederzeit widerrufen.'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Push Benachrichtigungen'),
            subtitle: const Text(
                'Deaktiviere Benachrichtigungen in den App Einstellungen.'),
          ),
          const Divider(height: 32),
          const _SectionTitle('Gefahrenzone'),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Account dauerhaft löschen',
              style: TextStyle(color: Colors.red),
            ),
            subtitle: const Text(
                'DSGVO Art. 17 – Recht auf Löschung. Alle Daten werden entfernt.'),
            onTap: () => _deleteAccount(context, ref),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  const _InfoCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text),
      ),
    );
  }
}
