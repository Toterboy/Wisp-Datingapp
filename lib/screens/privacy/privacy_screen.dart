import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/providers/mood_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/utils/constants.dart';

/// DSGVO-relevanter Datenschutz- und Account-Screen.
///
/// - Zeigt die verarbeiteten Daten an (knappe Übersicht).
/// - Ermöglicht den Export der eigenen Daten (E-01: lokale Daten als JSON
///   inkl. Auftragsverarbeiter-Liste; Chat-Verläufe sind E2E-verschlüsselt
///   und bleiben auf dem Gerät).
/// - Ermöglicht das vollständige Löschen des Accounts inkl. aller Daten.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _requestDataExport(BuildContext context, WidgetRef ref) async {
    // Lokale Daten bündeln (Profile, Einstellungen, Präferenzen, Mood).
    // Chat-Verläufe sind E2E-verschlüsselt und werden bewusst NICHT
    // exportiert — sie verbleiben auf dem Gerät.
    final profile = ref.read(profileProvider);
    final settings = ref.read(settingsProvider);
    final prefs = ref.read(userPreferencesProvider);

    final exportData = <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'Wisp Dating App',
      'userId': AppConstants.currentUserId,
      'profile': profile.toJson(),
      'settings': settings.toJson(),
      'preferences': prefs.toJson(),
      'mood': ref.read(moodProvider)?.value,
      'note': 'Chat-Verläufe sind Ende-zu-Ende verschlüsselt und verbleiben '
          'auf deinen Geräten. Sie werden von keinem Server verarbeitet '
          'und können daher nicht exportiert werden.',
      'processors': [
        {'name': 'Supabase Inc.', 'purpose': 'Hosting, Datenbank, Auth'},
        {'name': 'Google LLC (Firebase)', 'purpose': 'Push-Benachrichtigungen'},
        {'name': 'Hugging Face Inc.', 'purpose': 'NSFW-Foto-Moderation (nur Fotos)'},
        {'name': 'Apple Inc.', 'purpose': 'App-Store-Verteilung'},
      ],
    };
    final json = const JsonEncoder.withIndent('  ').convert(exportData);

    if (kIsWeb) {
      // Web kann keine Datei-Share-API nutzen: Inhalt im Dialog anzeigen.
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Deine Daten (JSON)'),
          content: SingleChildScrollView(
            child: SelectableText(json, style: const TextStyle(fontSize: 11)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/wisp_data_export.json');
      await file.writeAsString(json);
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            subject: 'Wisp Datenexport',
            text: 'Dein Wisp-Datenexport (JSON).',
          ),
        );
      } finally {
        // Temporäre Export-Datei (enthält alle Profildaten) wieder
        // löschen, damit nichts im Temp-Verzeichnis liegen bleibt
        // (Audit N2).
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Best effort.
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $e')),
        );
      }
    }
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
          const _SectionTitle('Auftragsverarbeiter'),
          const _InfoCard(
            text:
                'Folgende Dienstleister (Art. 28 DSGVO) verarbeiten Daten im '
                'Auftrag. Chat-Inhalte sind Ende-zu-Ende verschlüsselt und '
                'werden von keinem Dienstleister verarbeitet.',
          ),
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('Supabase Inc.'),
            subtitle: Text('Hosting, Datenbank, Authentifizierung (EU)'),
          ),
          const ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Google LLC (Firebase)'),
            subtitle: Text('Push-Benachrichtigungen'),
          ),
          const ListTile(
            leading: Icon(Icons.photo_filter_outlined),
            title: Text('Hugging Face Inc.'),
            subtitle: Text('NSFW-Foto-Moderation (nur Fotos, keine Chats)'),
          ),
          const ListTile(
            leading: Icon(Icons.storefront_outlined),
            title: Text('Apple Inc.'),
            subtitle: Text('App-Store-Verteilung'),
          ),
          const Divider(height: 32),
          const _SectionTitle('Einwilligungen'),
          const ListTile(
            leading: Icon(Icons.location_on),
            title: Text('Standortfreigabe'),
            subtitle: Text(
                'Du kannst die Standortfreigabe in den Systemeinstellungen '
                'deines Geräts jederzeit widerrufen.'),
          ),
          const ListTile(
            leading: Icon(Icons.notifications),
            title: Text('Push Benachrichtigungen'),
            subtitle: Text(
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
                'DSGVO Art. 17: Recht auf Löschung. Alle Daten werden entfernt.'),
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