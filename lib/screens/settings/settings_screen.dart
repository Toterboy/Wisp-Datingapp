import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:wisp/models/profile_visibility.dart';
import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/encryption_service.dart';
import 'package:wisp/services/mfa_service.dart';
import 'package:wisp/services/passkey_auth.dart';
import 'package:passkeys_doctor/passkeys_doctor.dart';
import 'package:wisp/services/prekey_service.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/unified_push_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/selectable_tile.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/widgets/language_switch.dart';
import 'package:wisp/widgets/theme_picker.dart';

/// Spiegelt die Benachrichtigungs-Schalter in die profiles-Tabelle, damit
/// die Push-Versendung (Edge Function notify-user) serverseitig gegatet
/// werden kann. Best effort.
void _persistNotifyFlags(WidgetRef ref) {
  if (!SupabaseService.isInitialized) return;
  unawaited(() async {
    try {
      final s = ref.read(settingsProvider);
      await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
        'notifications_enabled': s.notificationsEnabled,
        'notify_matches': s.notifyMatches,
        'notify_likes': s.notifyLikes,
        'notify_messages': s.notifyMessages,
        'notify_dating_hour': s.notifyDatingHour,
      });
    } catch (e) {
      debugPrint('[Settings] Notify-Flags-Server-Sync fehlgeschlagen: $e');
    }
  }());
}

/// Einstellungen: Blind Mode, Foto-Freigabe, Sichtbarkeit, Theme, Logout.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final profile = ref.watch(profileProvider);

    // Altersbasierte Sicherheits-Regeln anwenden
    final userAge = profile.age;
    if (kDebugMode) {
      // Geburtsdatum ist PII – nur im Debug-Modus loggen (Audit H4).
      debugPrint('[SETTINGS] profile.age=${profile.age}, birthDate=${profile.birthDate}, userAge=$userAge');
    }
    // Falls kein Alter bekannt (kein birthDate), Mindestalter 16 als Fallback für UI
    final effectiveAge = userAge ?? 16;
    final ageGroup = AgeSafetyRules.ageGroup(effectiveAge);
    final (allowedAgeMin, allowedAgeMax) = AgeSafetyRules.clampFilterAge(
      viewerAge: effectiveAge,
      filterMin: settings.ageRangeMin,
      filterMax: settings.ageRangeMax,
    );
    if (kDebugMode) {
      debugPrint('[SETTINGS] ageGroup=$ageGroup, allowedAgeMin=$allowedAgeMin, allowedAgeMax=$allowedAgeMax');
    }

    // Falls die aktuellen Werte außerhalb des erlaubten Bereichs liegen, korrigieren
    if (settings.ageRangeMin != allowedAgeMin || settings.ageRangeMax != allowedAgeMax) {
      // Async-Korrektur (nicht im build)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.setAgeRange(allowedAgeMin, allowedAgeMax);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Zurück',
          // P: Zurück zum aufrufenden Screen (Profil/Aktuelles). Falls die
          // Einstellungen direkt (z. B. Deep-Link) geöffnet wurden, fallback
          // auf "Aktuelles".
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          const _SectionTitle('Privatsphäre'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wer kann mein Profil sehen?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final v in ProfileVisibility.values)
                    SelectableTile<ProfileVisibility>(
                      value: v,
                      groupValue: settings.profileVisibility,
                      title: v.label,
                      onChanged: (val) {
                        if (val != null) notifier.setProfileVisibility(val);
                      },
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Deine Daten werden nur lokal auf diesem Gerät '
                    'gespeichert. Es werden keine unnötigen Berechtigungen '
                    'angefordert.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Community & Sicherheit'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.gavel),
                    title: const Text('Community Regeln'),
                    subtitle: const Text('Respektvoller Umgang & Verhaltensregeln'),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(AppRoutes.communityGuidelines),
                  ),
                  if (SupabaseService.isInitialized) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: const Text('Passkey erstellen'),
                      subtitle: const Text(
                        'Biometrischer Login (FaceID/TouchID) ohne Passwort',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      contentPadding: EdgeInsets.zero,
                      onTap: () async {
                        try {
                          await PasskeyAuth.register();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Passkey wurde erstellt.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            final msg = e is AppException
                                ? e.message
                                : 'Passkey-Erstellung fehlgeschlagen.';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Zwei-Faktor-Schutz (2FA)'),
                      subtitle: Text(
                        ref.watch(mfaStatusProvider).hasVerifiedFactors
                            ? 'Aktiv – Login nur mit Authenticator-Code'
                            : 'Login zusätzlich mit Authenticator-App sichern',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.push(AppRoutes.mfaSetup),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.notifications')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Push Benachrichtigungen',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Benachrichtigungen aktivieren'),
                    subtitle: const Text(
                      'Nachrichten, Likes, Matches und Event Erinnerungen',
                    ),
                    value: settings.notificationsEnabled,
                    onChanged: (v) {
                      notifier.setNotificationsEnabled(v);
                      _persistNotifyFlags(ref);
                    },
                  ),
                  const Divider(),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Neue Funken'),
                    subtitle: const Text('Wenn ein Funke entsteht'),
                    value: settings.notifyMatches,
                    onChanged: settings.notificationsEnabled
                        ? (v) {
                            notifier.setNotifyMatches(v);
                            _persistNotifyFlags(ref);
                          }
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Neue Likes'),
                    subtitle: const Text('Wenn dich jemand liked'),
                    value: settings.notifyLikes,
                    onChanged: settings.notificationsEnabled
                        ? (v) {
                            notifier.setNotifyLikes(v);
                            _persistNotifyFlags(ref);
                          }
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Chat Nachrichten'),
                    subtitle: const Text('Wenn dir jemand schreibt'),
                    value: settings.notifyMessages,
                    onChanged: settings.notificationsEnabled
                        ? (v) {
                            notifier.setNotifyMessages(v);
                            _persistNotifyFlags(ref);
                          }
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Dating Hour Erinnerung'),
                    subtitle: const Text('10 Minuten vor Beginn, wenn du dabei bist'),
                    value: settings.notifyDatingHour,
                    onChanged: settings.notificationsEnabled
                        ? (v) {
                            notifier.setNotifyDatingHour(v);
                            _persistNotifyFlags(ref);
                          }
                        : null,
                  ),
                  const Divider(),
                  const _UnifiedPushTile(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.appearance')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Erscheinungsbild',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  // String-Keys statt bool? (siehe Einrichtung):
                  // Radio mit null-Value verschluckt Taps.
                  SelectableTile<String>(
                    value: 'system',
                    groupValue: settings.useDarkMode == null
                        ? 'system'
                        : (settings.useDarkMode! ? 'dark' : 'light'),
                    title: 'System',
                    onChanged: (_) => notifier.setDarkMode(null),
                  ),
                  SelectableTile<String>(
                    value: 'light',
                    groupValue: settings.useDarkMode == null
                        ? 'system'
                        : (settings.useDarkMode! ? 'dark' : 'light'),
                    title: 'Hell',
                    onChanged: (_) => notifier.setDarkMode(false),
                  ),
                  SelectableTile<String>(
                    value: 'dark',
                    groupValue: settings.useDarkMode == null
                        ? 'system'
                        : (settings.useDarkMode! ? 'dark' : 'light'),
                    title: 'Dunkel',
                    onChanged: (_) => notifier.setDarkMode(true),
                  ),
                  const SizedBox(height: 12),
                  Text('Farbwelt',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ThemePicker(
                    selectedName: settings.themeName,
                    onChanged: (t) =>
                        ref.read(settingsProvider.notifier).setThemeName(t.name),
                  ),
                  const SizedBox(height: 16),
                  const LanguageSwitch(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.chatSafety')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    title: const Text('Bilder verpixelt anzeigen'),
                    subtitle: const Text(
                      'Schutz vor unangemessenen Inhalten: Bilder deiner '
                      'Gegenstelle werden erst nach Bestätigung gezeigt '
                      '(lang drücken zum Melden).',
                    ),
                    value: settings.blurChatImages,
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setBlurChatImages(v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.e2e')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Verschlüsseltes Key-Backup',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Sichert die private Identität deiner '
                    'Ende-zu-Ende-Verschlüsselung (passwortverschlüsselt, '
                    'AES-256-GCM). Nur damit kannst du nach Gerätewechsel '
                    'wieder verschlüsselt chatten. Verlust von Backup UND '
                    'Passwort ist unwiederbringlich.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Backup erstellen'),
                    subtitle:
                        const Text('Erzeugt einen verschlüsselten Code'),
                    contentPadding: EdgeInsets.zero,
                    onTap: SupabaseService.isInitialized
                        ? () => _createIdentityBackup(context, ref)
                        : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('Backup wiederherstellen'),
                    subtitle: const Text(
                        'Überschreibt die aktuelle E2E-Identität'),
                    contentPadding: EdgeInsets.zero,
                    onTap: SupabaseService.isInitialized
                        ? () => _restoreIdentityBackup(context, ref)
                        : null,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.monitor_heart_outlined),
                    title: const Text('Passkey-Diagnose'),
                    subtitle: const Text(
                        'Prüft Domain-Verknüpfung und Gerät auf Passkey-Tauglichkeit'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _runPasskeyDiagnostics(context),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.privacyAccount')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.health_and_safety_outlined),
                    title: const Text('Safety Center'),
                    subtitle: const Text(
                        'Hilfe bei Belästigung oder Stalking, Blockieren, Melden'),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(AppRoutes.safetyCenter),
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip),
                    title: const Text('Datenschutz & Account'),
                    subtitle: const Text(
                        'Gespeicherte Daten, Einwilligungen, Account löschen'),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(AppRoutes.privacy),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SecondaryButton(
            label: 'Abmelden',
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
          const SizedBox(height: 12),
          TextButton(
onPressed: () async {
              // Step-up (ASVS 7.5.3): Bei aktivem MFA ist vor der
              // Konto-Löschung eine zusätzliche TOTP-Verifikation nötig –
              // eine reine Passwort-Session (AAL1) reicht nicht.
              final mfa = ref.read(mfaStatusProvider);
              if (mfa.hasVerifiedFactors && mfa.currentAal != 'aal2') {
                final code = await _promptTotpCode(context);
                if (code == null || !context.mounted) return; // abgebrochen
                try {
                  await MfaService(SupabaseService.client)
                      .verifyChallenge(code: code);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Ungültiger oder abgelaufener Code. '
                          'Die Löschung wurde abgebrochen.',
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
                  title: const Text('Account löschen?'),
                  content: const Text(
                    'Dies löscht deinen Account permanent. '
                    'Diese Aktion kann nicht rückgängig gemacht werden.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Löschen'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                // Löschen + lokale Daten bereinigen. Die Navigation
                // übernimmt der Router automatisch (Auth-Status wird auf
                // "ausgeloggt" gesetzt -> Welcome/Login).
                await ref.read(authProvider.notifier).deleteAccount();
              }
            },
            child: Text(
              'Account löschen',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          const SizedBox(height: 24),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data;
              if (version == null) return const SizedBox.shrink();
              return Text(
                'Version ${version.version} (Build ${version.buildNumber})',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// Fragt den 6-stelligen TOTP-Code für das Step-up vor der Konto-Löschung
/// ab. Liefert `null`, wenn der Nutzer abgebrochen hat.
Future<String?> _promptTotpCode(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Konto bestätigen'),
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
          child: const Text('Bestätigen'),
        ),
      ],
    ),
  );
}



// ===========================================================================
// E2E-Identität: verschlüsseltes Key-Backup (Migration Roadmap 0.6)
// ===========================================================================

/// Erstellt ein passwortverschlüsseltes Backup der Signal-Identität und
/// zeigt es zum Kopieren an. Der Nutzer bewahrt den Code selbst auf
/// (Passwortmanager/Papier) - kein Cloud-Zwang.
Future<void> _createIdentityBackup(
  BuildContext context,
  WidgetRef ref,
) async {
  final pwCtrl = TextEditingController();
  final pw2Ctrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Backup-Passwort wählen'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: pwCtrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Passwort (min. 8 Zeichen)',
              ),
              validator: (v) =>
                  v != null && v.length >= 8 ? null : 'Zu kurz (min. 8)',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: pw2Ctrl,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Passwort wiederholen'),
              validator: (v) => v == pwCtrl.text ? null : 'Passwörter stimmen nicht überein',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(formKey.currentState!.validate()),
          child: const Text('Backup erstellen'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final blob = await ref
      .read(encryptionServiceProvider)
      .createEncryptedBackup(pwCtrl.text);
  if (!context.mounted) return;
  if (blob == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup konnte nicht erstellt werden.')),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Dein Backup-Code'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(blob,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              const SizedBox(height: 12),
              Text(
                'Bewahre Code UND Passwort sicher auf (z. B. Passwort-'
                'Manager). Ohne beides ist eine Wiederherstellung unmöglich.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: blob));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Backup-Code kopiert.')),
            );
          },
          icon: const Icon(Icons.copy),
          label: const Text('Kopieren'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Fertig'),
        ),
      ],
    ),
  );
}

/// Stellt die E2E-Identität aus einem Backup-Code wieder her und
/// veröffentlicht anschließend frische PreKeys auf dem Server, damit
/// Partner wieder verschlüsselte Sessions aufbauen können.
Future<void> _restoreIdentityBackup(
  BuildContext context,
  WidgetRef ref,
) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Identität wiederherstellen?'),
      content: const Text(
        'Die aktuelle E2E-Identität auf diesem Gerät wird ÜBERSCHRIEBEN '
        '(bestehende verschlüsselte Sitzungen gehen verloren). Verwende nur '
        'ein Backup deines eigenen Kontos.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Weiter'),
        ),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return;

  final blobCtrl = TextEditingController();
  final pwCtrl = TextEditingController();
  final restored = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Backup eingeben'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: blobCtrl,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Backup-Code einfügen',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pwCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Backup-Passwort'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Wiederherstellen'),
        ),
      ],
    ),
  );
  if (restored != true || !context.mounted) return;

  try {
    await ref
        .read(encryptionServiceProvider)
        .restoreFromBackup(blobCtrl.text.trim(), pwCtrl.text);
    // Frische PreKeys veröffentlichen, damit Partner wieder Sessions
    // aufbauen können (das Backup enthält keine One-Time-PreKeys).
    await ref.read(preKeyServiceProvider).publishOwnPreKeysFromStore();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('E2E-Identität wiederhergestellt.')),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Wiederherstellung fehlgeschlagen. Prüfe Code und Passwort.'),
      ),
    );
  }
}

/// Schalter fuer Google-freien Push via UnifiedPush (F-Droid-Variante).
///
/// Benoetigt eine Distributor-App (z. B. ntfy). Der Endpunkt wird
/// serverseitig im Profil gespeichert; eingehende Pushes zeigt der
/// [UnifiedPushService] lokal an.
class _UnifiedPushTile extends ConsumerStatefulWidget {
  const _UnifiedPushTile();

  @override
  ConsumerState<_UnifiedPushTile> createState() => _UnifiedPushTileState();
}

class _UnifiedPushTileState extends ConsumerState<_UnifiedPushTile> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    UnifiedPushService.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _toggle(bool want) async {
    setState(() => _busy = true);
    try {
      if (want) {
        await UnifiedPushService.enable();
      } else {
        await UnifiedPushService.disable();
      }
      final active = await UnifiedPushService.isEnabled();
      if (mounted) setState(() => _enabled = active);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled ?? false;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: const Text('Push ohne Google (UnifiedPush)'),
      subtitle: Text(
        enabled
            ? 'Aktiv - Endpunkt ist hinterlegt.'
            : 'Ben\u00f6tigt eine Distributor-App wie ntfy '
                '(F-Droid). FCM bleibt in der Play-Variante aktiv.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: enabled,
      onChanged: _busy ? null : (v) => _toggle(v),
    );
  }
}

/// Fuehrt die Passkeys-Doctor-Checks aus (RP-ID-Wert, assetlinks.json,
/// Geraet) und zeigt jeden Checkpoint mit Ergebnis - so sieht der Nutzer
/// die GENAUE Ursache, warum Passkeys fehlschlagen.
Future<void> _runPasskeyDiagnostics(BuildContext context) async {
  const rpId = 'auth.wispdating.de';
  final doctor = PasskeysDoctor();
  final checkpoints = <Checkpoint>[];
  final completer = Completer<List<Checkpoint>>();
  late final StreamSubscription<Result> sub;

  sub = doctor.resultStream.listen((result) {
    if (!completer.isCompleted) completer.complete(result.checkpoints);
  });

  // Dialog mit Spinner waehrend der Pruefung.
  var done = false;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AlertDialog(
      title: Text('Passkey-Diagnose'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Pruefe Geraet und Domain-Verknuepfung...'),
        ],
      ),
    ),
  ));

  try {
    await doctor.check(rpId);
    final result = await completer.future
        .timeout(const Duration(seconds: 20), onTimeout: () => checkpoints);
    checkpoints.addAll(result);
  } catch (e) {
    checkpoints.add(Checkpoint(
      name: 'Diagnose-Fehler',
      description: e.toString(),
      type: CheckpointType.error,
    ));
  } finally {
    sub.cancel();

    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Passkey-Diagnose'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final cp in checkpoints)
              ListTile(
                leading: Icon(
                  cp.type == CheckpointType.success
                      ? Icons.check_circle
                      : Icons.error,
                  color: cp.type == CheckpointType.success
                      ? Colors.green
                      : Theme.of(ctx).colorScheme.error,
                ),
                title: Text(cp.name),
                subtitle: SelectableText(cp.description),
                isThreeLine: cp.description.length > 60,
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  done = done; // Vermeidet unused_warning in strengen Setups.
}
