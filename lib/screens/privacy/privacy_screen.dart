import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/providers/mood_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/mfa_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/constants.dart';

/// DSGVO-relevanter Datenschutz- und Account-Screen.
///
/// - Zeigt die verarbeiteten Daten an (knappe Ãœbersicht).
/// - ErmÃ¶glicht den Export der eigenen Daten (E-01: lokale Daten als JSON
///   inkl. Auftragsverarbeiter-Liste; Chat-VerlÃ¤ufe sind E2E-verschlÃ¼sselt
///   und bleiben auf dem GerÃ¤t).
/// - ErmÃ¶glicht das vollstÃ¤ndige LÃ¶schen des Accounts inkl. aller Daten.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _requestDataExport(BuildContext context, WidgetRef ref) async {
    // Lokale Daten bÃ¼ndeln (Profile, Einstellungen, PrÃ¤ferenzen, Mood).
    // Chat-VerlÃ¤ufe sind E2E-verschlÃ¼sselt und werden bewusst NICHT
    // exportiert â€” sie verbleiben auf dem GerÃ¤t.
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
      'note': 'Chat-VerlÃ¤ufe sind Ende-zu-Ende verschlÃ¼sselt und verbleiben '
          'auf deinen GerÃ¤ten. Sie werden von keinem Server verarbeitet '
          'und kÃ¶nnen daher nicht exportiert werden.',
      'processors': [
        {'name': 'Supabase Inc.', 'purpose': 'Hosting, Datenbank, Auth'},
        {'name': 'Google LLC (Firebase)', 'purpose': 'Push-Benachrichtigungen'},
        {'name': 'Brevo', 'purpose': 'Transaktions-E-Mails'},
        {'name': 'Cloudflare Inc.', 'purpose': 'CAPTCHA (Turnstile), TURN'},
        {'name': 'Netlify Inc.', 'purpose': 'Hosting Auth-/CAPTCHA-Seite'},
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
          title: Text(L10n.t(context, 'privacy.yourData')),
          content: SingleChildScrollView(
            child: SelectableText(json, style: const TextStyle(fontSize: 11)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10n.t(context, 'common.ok')),
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
        // TemporÃ¤re Export-Datei (enthÃ¤lt alle Profildaten) wieder
        // lÃ¶schen, damit nichts im Temp-Verzeichnis liegen bleibt
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
          SnackBar(
              content:
                  Text('${L10n.t(context, 'privacy.exportFailed')}: $e')),
        );
      }
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    // Step-up (ASVS 7.5.3): Bei aktivem MFA ist vor der Konto-LÃ¶schung
    // eine zusÃ¤tzliche TOTP-Verifikation nÃ¶tig â€“ eine reine Passwort-
    // Session (AAL1) reicht nicht (die Edge Function erzwingt AAL2
    // serverseitig; der Pre-Check hier liefert die verstÃ¤ndliche
    // Fehlermeldung statt eines kryptischen Server-Fehlers).
    final mfa = ref.read(mfaStatusProvider);
    if (mfa.hasVerifiedFactors && mfa.currentAal != 'aal2') {
      final code = await promptTotpCode(context);
      if (code == null || !context.mounted) return; // abgebrochen
      try {
        await MfaService(SupabaseService.client).verifyChallenge(code: code);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'UngÃ¼ltiger oder abgelaufener Code. '
                'Die LÃ¶schung wurde abgebrochen.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'privacy.deleteTitle')),
        content: Text(L10n.t(context, 'privacy.deleteBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(L10n.t(context, 'privacy.deleteConfirm')),
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
          SnackBar(
              content:
                  Text('${L10n.t(context, 'privacy.deleteFailed')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'privacy.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(L10n.t(context, 'privacy.yourData')),
          _InfoCard(text: L10n.t(context, 'privacy.dataInfo')),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.download),
            title: Text(L10n.t(context, 'privacy.export')),
            subtitle: Text(L10n.t(context, 'privacy.exportSub')),
            onTap: () => _requestDataExport(context, ref),
          ),
          const Divider(height: 32),
          _SectionTitle(L10n.t(context, 'privacy.processors')),
          _InfoCard(text: L10n.t(context, 'privacy.processorsInfo')),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Supabase Inc.'),
            subtitle: Text(L10n.t(context, 'privacy.processorSupabase')),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Google LLC (Firebase)'),
            subtitle: Text(L10n.t(context, 'privacy.processorGoogle')),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Brevo'),
            subtitle: Text(L10n.t(context, 'privacy.processorBrevo')),
          ),
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Cloudflare Inc.'),
            subtitle: Text(L10n.t(context, 'privacy.processorCloudflare')),
          ),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: const Text('Netlify Inc.'),
            subtitle: Text(L10n.t(context, 'privacy.processorNetlify')),
          ),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Apple Inc.'),
            subtitle: Text(L10n.t(context, 'privacy.processorApple')),
          ),
          const Divider(height: 32),
          _SectionTitle(L10n.t(context, 'privacy.consent')),
          // Standortfreigabe: Direkter Sprung in die System-Standort-
          // Einstellungen (Einwilligung OS-seitig widerrufbar).
          ListTile(
            leading: const Icon(Icons.location_on),
            title: Text(L10n.t(context, 'privacy.location')),
            subtitle: Text(L10n.t(context, 'privacy.locationSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Geolocator.openLocationSettings(),
          ),
          // Push: Ã–ffnet die App-Einstellungen des Betriebssystems
          // (Android: Benachrichtigungen sind dort ein Tap entfernt).
          ListTile(
            leading: const Icon(Icons.notifications),
            title: Text(L10n.t(context, 'privacy.push')),
            subtitle: Text(L10n.t(context, 'privacy.pushSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openAppSettings(),
          ),
          const Divider(height: 32),
          _SectionTitle(L10n.t(context, 'privacy.dangerZone')),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: Text(
              L10n.t(context, 'privacy.deleteAccount'),
              style: const TextStyle(color: Colors.red),
            ),
            subtitle: Text(L10n.t(context, 'privacy.deleteAccountSub')),
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

/// Fragt den 6-stelligen TOTP-Code fÃ¼r das Step-up vor einer sensiblen
/// Aktion (Konto-LÃ¶schung, Passkey-Erstellung) ab.
/// Liefert `null`, wenn der Nutzer abgebrochen hat.
Future<String?> promptTotpCode(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Konto bestÃ¤tigen'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(
          labelText: 'TOTP-Code (Authenticator-App)',
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('BestÃ¤tigen'),
        ),
      ],
    ),
  );
}
