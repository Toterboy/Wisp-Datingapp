import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/gender.dart';
import 'package:wisp/models/user_mood.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/widgets/profile_widgets.dart';

/// Versucht, ein Nutzerprofil anhand seiner ID aus den verfügbaren Quellen
/// aufzulösen (eigenes Profil, Matches). Liefert null, wenn kein Profil in
/// den synchronen Quellen gefunden wurde — der Aufrufer kann dann asynchron
/// die Supabase public_profiles-View abfragen.
UserProfile? resolveProfileById(WidgetRef ref, String userId) {
  if (userId.isEmpty) return null;

  // Eigenes Profil.
  final me = ref.read(profileProvider);
  if (me.id == userId) return me;

  // Partner aus bestehenden Matches.
  for (final match in ref.read(chatProvider)) {
    if (match.partner.id == userId) return match.partner;
  }

  return null;
}

/// Öffentliches Profil eines anderen Nutzers (aus Chat oder Matches).
///
/// Zeigt nur die Infos, die laut Alters-Sichtbarkeitsregeln erlaubt sind
/// (z. B. Fotos erst nach Match). Bietet keinen Bearbeiten-Button.
///
/// Lädt das fremde Profil aus mehreren Quellen: synchron aus Matches/
/// Vorschlägen, asynchron als Fallback aus der Supabase public_profiles-View.
class ProfileDetailScreen extends ConsumerStatefulWidget {
  const ProfileDetailScreen({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<ProfileDetailScreen> createState() =>
      _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<ProfileDetailScreen> {
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userId = widget.userId;
    // Synchron aus bekannten Quellen.
    var profile = resolveProfileById(ref, userId);

    // Asynchroner Fallback: Supabase public_profiles-View.
    if (profile == null) {
      try {
        final db = ref.read(supabaseDatabaseServiceProvider);
        final row = await db.fetchPublicProfile(userId);
        if (row != null) {
          profile = UserProfile.fromPublicView(row);
        }
      } catch (_) {
        // Kein Supabase verfügbar oder User nicht gefunden.
      }
    }

    if (mounted) setState(() => _profile = profile);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    if (profile == null) {
      // Profil konnte nicht aufgelöst werden (z. B. Demo-Mock ohne Daten).
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.home);
              }
            },
          ),
          title: const Text('Profil'),
        ),
        body: const Center(
          child: Text('Dieses Profil ist derzeit nicht verfügbar.'),
        ),
      );
    }

    final settings = ref.watch(settingsProvider);
    final me = ref.watch(profileProvider);

    final genderLabel = profile.gender != null && profile.gender!.isNotEmpty
        ? Gender.fromValue(profile.gender)?.label ?? ''
        : '';

    final isPhotosVisible = AgeSafetyRules.arePhotosVisible(
      targetAge: profile.age ?? 16,
      viewerAge: me.age ?? 16,
      blindModeEnabled: settings.blindModeEnabled,
      revealPhotosAfterMatch: settings.revealPhotosAfterMatch,
      isMatched: true, // Im Kontext von Chat/Matches ist ein Match gegeben.
    );
    debugPrint('[PROFILE_DETAIL] targetAge=${profile.age}, viewerAge=${me.age}, targetBirthDate=${profile.birthDate}, viewerBirthDate=${me.birthDate}');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Zurück zur vorherigen Seite (Chat/Matches), falls möglich.
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.interessen);
            }
          },
        ),
        title: Text(profile.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: CircleAvatar(
                radius: 52,
                child: !isPhotosVisible
                    ? const Icon(Icons.visibility_off, size: 48)
                    : const Icon(Icons.person, size: 56),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                '${profile.name}${profile.age != null && profile.age! > 0 ? ', ${profile.age}' : ''}'
                '${genderLabel.isNotEmpty ? ' · $genderLabel' : ''}'
                '${profile.city.isNotEmpty ? ' · ${profile.city}' : ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (profile.personalityType != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Chip(label: Text('Typ ${profile.personalityType}')),
              ),
            ],
            if (profile.mood != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Chip(
                  avatar: Icon(
                    Mood.fromValue(profile.mood)?.icon ?? Icons.mood,
                    size: 18,
                    color: Mood.fromValue(profile.mood)?.color,
                  ),
                  label: Text(
                    'Mood: ${Mood.fromValue(profile.mood)?.label ?? profile.mood}',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (isPhotosVisible)
              Container(
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Colors.deepPurple, Colors.blue],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.person, color: Colors.white, size: 48),
                ),
              ),
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
            ],
          ],
        ),
      ),
    );
  }
}

