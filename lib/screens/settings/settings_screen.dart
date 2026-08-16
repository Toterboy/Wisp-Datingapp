import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:wisp/models/profile_visibility.dart';
import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/selectable_tile.dart';

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
    debugPrint('[SETTINGS] profile.age=${profile.age}, birthDate=${profile.birthDate}, userAge=$userAge');
    // Falls kein Alter bekannt (kein birthDate), Mindestalter 16 als Fallback für UI
    final effectiveAge = userAge ?? 16;
    final ageGroup = AgeSafetyRules.ageGroup(effectiveAge);
    final (allowedAgeMin, allowedAgeMax) = AgeSafetyRules.clampFilterAge(
      viewerAge: effectiveAge,
      filterMin: settings.ageRangeMin,
      filterMax: settings.ageRangeMax,
    );
    debugPrint('[SETTINGS] ageGroup=$ageGroup, allowedAgeMin=$allowedAgeMin, allowedAgeMax=$allowedAgeMax');

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
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Benachrichtigungen'),
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
                    title: const Text('Neue Matches'),
                    subtitle: const Text('Wenn ein Match entsteht'),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Darstellung'),
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
                  SelectableTile<bool?>(
                    value: null,
                    groupValue: settings.useDarkMode,
                    title: 'System',
                    onChanged: (v) => notifier.setDarkMode(v),
                  ),
                  SelectableTile<bool?>(
                    value: false,
                    groupValue: settings.useDarkMode,
                    title: 'Hell',
                    onChanged: (v) => notifier.setDarkMode(v),
                  ),
                  SelectableTile<bool?>(
                    value: true,
                    groupValue: settings.useDarkMode,
                    title: 'Dunkel',
                    onChanged: (v) => notifier.setDarkMode(v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Datenschutz & Account'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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


