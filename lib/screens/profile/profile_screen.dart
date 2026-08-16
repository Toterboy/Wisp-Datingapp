import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import 'package:wisp/models/app_settings.dart';
import 'package:wisp/models/gender.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/mood_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/screens/admin/admin_screen.dart';
import 'package:wisp/services/supabase_storage_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/widgets/profile_widgets.dart';

/// Profil-Anzeige des eigenen Nutzers mit Schnellzugriff auf Bearbeiten,
/// Einstellungen, Spenden und Empfehlen.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final settings = ref.watch(settingsProvider);

    final genderLabel = profile.gender != null && profile.gender!.isNotEmpty
        ? Gender.fromValue(profile.gender)?.label ?? ''
        : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mein Profil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Mein QR Code',
            onPressed: () => context.push(AppRoutes.qrProfile),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: CircleAvatar(
                radius: 52,
                child: Icon(Icons.person, size: 56),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Versteckter Admin-Zugang: Long-Press auf den Namen
                  // oeffnet nur fuer die konfigurierte Admin-ID den
                  // Admin-Bereich. Normale Nutzer erreichen ihn nicht.
                  GestureDetector(
                    onLongPress: isCurrentUserAdmin()
                        ? () => context.go(AppRoutes.admin)
                        : null,
                    child: Text(
                      profile.name.isEmpty ? 'Unbekannt' : profile.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: Text(
                '${profile.age != null ? '${profile.age} Jahre' : 'Alter unbekannt'}'
                '${genderLabel.isNotEmpty ? ' · $genderLabel' : ''}'
                '${profile.city.isNotEmpty ? ' · ${profile.city}' : ''}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (profile.personalityType != null) ...[
              const SizedBox(height: 4),
              Center(
                child: Chip(
                  label: Text('Typ ${profile.personalityType}'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('über mich',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      profile.bio.isEmpty ? 'Noch keine Bio.' : profile.bio,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (profile.interests.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Interessen',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      InterestChips(interests: profile.interests),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const _MoodCard(),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                title: const Text('Persönlichkeit vor Aussehen'),
                subtitle: const Text('Fotos erst nach Match anzeigen'),
                value: settings.blindModeEnabled,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).toggleBlindMode(v),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showProfileMenu(context, ref, profile, settings),
              icon: const Icon(Icons.person),
              label: const Text('Profil'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.bugReport),
              icon: const Icon(Icons.bug_report),
              label: const Text('Bug melden'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Profil-Menü: Profil bearbeiten, Profil Vorschau, Vorstellung Vorschau.
  void _showProfileMenu(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    AppSettings settings,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Profil bearbeiten'),
              subtitle: const Text('Daten, Interessen und Vorstellung ändern'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push(AppRoutes.profileEdit);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('Profil Vorschau'),
              subtitle: const Text('So sehen dich andere'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showProfilePreview(context, ref, profile, settings);
              },
            ),
            ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: const Text('Vorstellung Vorschau'),
              subtitle: const Text('Deine Text- und Audio-Vorstellung ansehen'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showIntroPreview(context, ref, profile);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Vorschau der eigenen Vorstellung (Text + Audio) für "Find your Match".
  void _showIntroPreview(BuildContext context, WidgetRef ref, UserProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Meine Vorstellung',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (profile.introText.isEmpty)
                const Text(
                  'Du hast noch keine Text-Vorstellung hinterlegt.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                Text(
                  profile.introText,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              const SizedBox(height: 16),
              _OwnIntroAudioPlayer(
                userId: profile.id,
                hasAudio: profile.introAudioPath != null,
              ),
              const SizedBox(height: 16),
              Text(
                'Andere lernen dich über diese Vorstellung kennen, bevor '
                'sie ein Foto sehen. Bearbeiten kannst du sie unter '
                'Profil bearbeiten.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Zeigt eine Vorschau des eigenen Profils, wie es für andere sichtbar ist.
  void _showProfilePreview(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    AppSettings settings,
  ) {
    final myAge = profile.age ?? 16;
    debugPrint('[PROFILE_SCREEN] profile.age=${profile.age}, birthDate=${profile.birthDate}, myAge=$myAge');
    final isPhotosVisible = AgeSafetyRules.arePhotosVisible(
      targetAge: myAge,
      viewerAge: myAge, // Selbst-Vorschau: gleiches Alter
      blindModeEnabled: settings.blindModeEnabled,
      revealPhotosAfterMatch: settings.revealPhotosAfterMatch,
      isMatched: true, // Bei Vorschau davon ausgehen, dass Match besteht
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Profil Vorschau',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'So sehen dich andere Nutzer (inkl. Alters Schutz & Blind Mode):',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              Center(
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: isPhotosVisible
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.grey.shade300,
                  child: !isPhotosVisible
                      ? const Icon(Icons.visibility_off, size: 48, color: Colors.white)
                      : const Icon(Icons.person, size: 56, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '${profile.name}${profile.age != null ? ', ${profile.age}' : ''}'
                  '${profile.gender != null && profile.gender!.isNotEmpty ? ' · ${Gender.fromValue(profile.gender!)?.label ?? profile.gender}' : ''}'
                  '${profile.city.isNotEmpty ? ' · ${profile.city}' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              if (profile.personalityType != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Chip(label: Text('Typ ${profile.personalityType}')),
                ),
              ],
              if (!isPhotosVisible) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Theme.of(context).colorScheme.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Deine Fotos sind aufgrund deiner Einstellungen '
                          '(Persönlichkeit vor Aussehen / Alters Schutz) '
                          'für andere nicht sichtbar.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('über mich',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        profile.bio.isEmpty ? 'Noch keine Bio.' : profile.bio,
                      ),
                    ],
                  ),
                ),
              ),
              if (profile.interests.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Interessen',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        InterestChips(interests: profile.interests),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Hinweis: Die tatsächliche Sichtbarkeit hängt vom Alter '
                'und den Einstellungen der jeweiligen Betrachter ab.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card mit aktuellem Mood of the Day und Button zum Ändern.
class _MoodCard extends ConsumerWidget {
  const _MoodCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mood = ref.watch(moodProvider);
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: mood?.color.withValues(alpha: 0.15) ??
                theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            mood?.icon ?? Icons.emoji_emotions_outlined,
            color: mood?.color ?? theme.colorScheme.primary,
          ),
        ),
        title: Text(
          mood != null ? 'Heute ${mood.label}' : 'Kein Mood ausgewählt',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          mood != null
              ? 'Tippe, um deine Stimmung zu ändern.'
              : 'Tippe, um deine Stimmung des Tages zu wählen.',
          style: theme.textTheme.bodySmall,
        ),
        trailing: TextButton(
          onPressed: () => context.push(AppRoutes.moodPicker),
          child: Text(mood != null ? 'Ändern' : 'Wählen'),
        ),
      ),
    );
  }
}

/// Spielt die EIGENE Audio-Vorstellung ab (signierte URL des eigenen
/// Storage-Pfads - keine match-media-Berechtigung nötig).
class _OwnIntroAudioPlayer extends ConsumerStatefulWidget {
  const _OwnIntroAudioPlayer({required this.userId, required this.hasAudio});

  final String userId;
  final bool hasAudio;

  @override
  ConsumerState<_OwnIntroAudioPlayer> createState() =>
      _OwnIntroAudioPlayerState();
}

class _OwnIntroAudioPlayerState extends ConsumerState<_OwnIntroAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final storage = ref.read(supabaseStorageServiceProvider);
      final url =
          await storage.getSignedAvatarUrl('${widget.userId}/intro.m4a');
      if (url == null) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audio-Vorstellung nicht gefunden.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await _player.setUrl(url);
      await _player.play();
      if (mounted) setState(() => _playing = true);
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() => _playing = false);
        }
      });
    } catch (e) {
      debugPrint('[OwnIntro] Fehler: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio-Vorstellung konnte nicht geladen werden.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasAudio) {
      return const Text(
        'Noch keine Audio-Vorstellung hinterlegt.',
        style: TextStyle(color: Colors.grey),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: _toggle,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_playing ? Icons.stop : Icons.play_arrow),
      label: Text(_playing ? 'Stopp' : 'Audio-Vorstellung anhören'),
    );
  }
}
