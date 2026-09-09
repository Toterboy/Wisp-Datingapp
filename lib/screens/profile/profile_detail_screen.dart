import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/gender.dart';
import 'package:wisp/models/user_mood.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_storage_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/widgets/profile_widgets.dart';
import 'package:wisp/widgets/music_taste_widgets.dart';

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
  double? _distanceKm;

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

    // Distanz in km (5-km-Schritte, serverseitig berechnet) - optional.
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final distance = await db.fetchDistanceKm(userId);
      if (mounted) setState(() => _distanceKm = distance);
    } catch (_) {}

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
body: Center(
child: Text(L10n.t(context, 'profile.detail.unavailable')),
),
      );
    }

    final settings = ref.watch(settingsProvider);
    final me = ref.watch(profileProvider);

    final genderLabel = profile.gender != null && profile.gender!.isNotEmpty
        ? (Gender.fromValue(profile.gender) != null
            ? L10n.t(context, Gender.fromValue(profile.gender)!.labelKey)
            : '')
        : '';

    final isPhotosVisible = AgeSafetyRules.arePhotosVisible(
      targetAge: profile.age ?? 16,
      viewerAge: me.age ?? 16,
      blindModeEnabled: settings.blindModeEnabled,
      revealPhotosAfterMatch: settings.revealPhotosAfterMatch,
      isMatched: true, // Im Kontext von Chat/Matches ist ein Match gegeben.
    );
    // Audit M-18: Geburtsdaten (auch fremder Nutzer!) sind PII - nur im
    // Debug-Build loggen.
    if (kDebugMode) {
      debugPrint('[PROFILE_DETAIL] targetAge=${profile.age}, viewerAge=${me.age}, '
          'targetBirthDate=${profile.birthDate}, viewerBirthDate=${me.birthDate}');
    }

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
        actions: [
          // "Profil lokal speichern" (v0.9.1): Fremde Profile (z. B. per
          // QR gescannt, ohne Internet) lokal behalten, um sie später
          // anzuschreiben. Max. 5, einzeln löschbar. Für das eigene Profil
          // ausgeblendet.
          if (me.id != profile.id)
            _SavedProfileAction(profile: profile),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _PublicProfileAvatar(
                profile: profile,
                isPhotosVisible: isPhotosVisible,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '${profile.name}${profile.age != null && profile.age! > 0 ? ', ${profile.age}' : ''}'
                      '${genderLabel.isNotEmpty ? ' · $genderLabel' : ''}'
                      '${(profile.state ?? '').isNotEmpty ? ' · ${profile.state}' : ''}'
                      '${profile.city.isNotEmpty && (profile.state ?? '').isEmpty ? ' · ${profile.city}' : ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Verifiziert-Badge (serverseitig durch Admin-Freigabe).
                  if (profile.isVerified) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Verifiziert',
                      child: Icon(
                        Icons.verified,
                        size: 20,
                        color: Colors.lightBlue.shade400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_distanceKm != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  // Nur die gerundete Entfernung - nie der exakte Standort.
                  _distanceKm!.round() == 0
                      ? 'unter 5 km entfernt'
                      : 'ca. ${_distanceKm!.round()} km entfernt',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            ],
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
                    'Mood: ${Mood.fromValue(profile.mood) != null ? L10n.t(context, Mood.fromValue(profile.mood)!.labelKey) : (profile.mood ?? '')}',
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
                    Text(L10n.t(context, 'profile.detail.aboutMe'),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      profile.bio.isEmpty
                          ? L10n.t(context, 'profile.detail.noBio')
                          : profile.bio,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (profile.interests.isNotEmpty) ...[
              Builder(builder: (context) {
                // Gemeinsame Interessen mit dem eigenen Profil hervorheben.
                final me = ref.watch(profileProvider);
                final common =
                    profile.interests.where(me.interests.contains).toList();
                final others =
                    profile.interests.where((i) => !me.interests.contains(i)).toList();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L10n.t(context, 'profile.detail.interests'),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        if (common.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(Icons.favorite,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(L10n.t(context, 'profile.detail.commonWithYou'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      )),
                            ],
                          ),
                          const SizedBox(height: 8),
                          InterestChips(interests: common, highlighted: true),
                          const SizedBox(height: 12),
                        ],
                        if (others.isNotEmpty) ...[
                          if (common.isNotEmpty)
                            Text(L10n.t(context, 'profile.detail.more'),
                                style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 8),
                          InterestChips(interests: others),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
            // Musik-Geschmack (v0.8.0): gemeinsame Genres hervorgehoben.
            if (profile.musicLiked.isNotEmpty ||
                profile.musicDisliked.isNotEmpty) ...[
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final me = ref.watch(profileProvider);
                final common =
                    profile.musicLiked.where(me.musicLiked.contains).toList();
                final others =
                    profile.musicLiked.where((g) => !me.musicLiked.contains(g)).toList();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.music_note,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(L10n.t(context, 'profile.detail.music'),
                                style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (common.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(Icons.favorite,
                                  size: 16,
                                  color:
                                      Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(L10n.t(context, 'profile.detail.sameTaste'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      )),
                            ],
                          ),
                          const SizedBox(height: 8),
                          MusicTasteView(
                            liked: common,
                            commonWith: common,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (others.isNotEmpty) ...[
                          if (common.isNotEmpty)
                            Text(L10n.t(context, 'profile.detail.more'),
                                style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 8),
                          MusicTasteView(liked: others),
                        ],
                        if (profile.musicDisliked.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          MusicTasteView(liked: const [], disliked: profile.musicDisliked),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}



/// Profilbild des FREMDEN Nutzers (v0.8.1-Fix): Vorher wurde hier nur ein
/// Person-Platzhalter gezeigt, weil der public_profiles-View die photos-
/// Spalte nicht enthielt (Migration 077) und der Screen das Bild gar
/// nicht lud. Jetzt: Bytes aus dem Storage-Cache laden und anzeigen.
/// Respektiert Blind Mode / Foto-Freischaltung (isPhotosVisible).
class _PublicProfileAvatar extends ConsumerStatefulWidget {
  const _PublicProfileAvatar({
    required this.profile,
    required this.isPhotosVisible,
  });

  final UserProfile profile;
  final bool isPhotosVisible;

  @override
  ConsumerState<_PublicProfileAvatar> createState() =>
      _PublicProfileAvatarState();
}

class _PublicProfileAvatarState extends ConsumerState<_PublicProfileAvatar> {
  Future<Uint8List?>? _avatarFuture;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(covariant _PublicProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Neues Bild (neue Referenz) -> neu laden.
    final oldRef =
        oldWidget.profile.photos.isNotEmpty ? oldWidget.profile.photos.first : null;
    final newRef =
        widget.profile.photos.isNotEmpty ? widget.profile.photos.first : null;
    if (oldRef != newRef) _loadAvatar();
  }

  void _loadAvatar() {
    final path = widget.profile.photos.isNotEmpty
        ? widget.profile.photos.first
        : null;
    if (path == null) {
      _avatarFuture = null;
      return;
    }
    _avatarFuture = ref
        .read(supabaseStorageServiceProvider)
        .loadAvatarBytes(path);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPhotosVisible) {
      return const CircleAvatar(
        radius: 52,
        child: Icon(Icons.visibility_off, size: 48),
      );
    }
    if (_avatarFuture == null) {
      return const CircleAvatar(
        radius: 52,
        child: Icon(Icons.person, size: 56),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _avatarFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return CircleAvatar(
            radius: 52,
            backgroundImage: MemoryImage(bytes),
          );
        }
        // Cache-Treffer kommen synchron an; während des ersten Downloads
        // dezent der Platzhalter statt einesextra Spinners.
        return const CircleAvatar(
          radius: 52,
          child: Icon(Icons.person, size: 56),
        );
      },
    );
  }
}

/// AppBar-Aktion "Profil lokal speichern" (v0.9.1): Erzeugt einen
/// PERSISTENTEN QR-Kontakt aus dem geladenen Profil (funktioniert auch
/// ohne Internet, da die Profil-Daten lokal übernommen werden). Max. 5;
/// bereits gespeicherte Profile lassen sich hier wieder entfernen.
class _SavedProfileAction extends ConsumerWidget {
  const _SavedProfileAction({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(chatProvider);
    final existing = contacts
        .where((m) => m.isQrContact && m.partner.id == profile.id)
        .firstOrNull;

    if (existing != null) {
      return IconButton(
        icon: const Icon(Icons.bookmark),
        tooltip: L10n.t(context, 'profile.detail.savedRemove'),
        onPressed: () {
          ref.read(chatProvider.notifier).deleteQrContact(existing.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  L10n.tf(context, 'profile.detail.savedRemoved',
                      {'name': profile.name})),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
    }

    return IconButton(
      icon: const Icon(Icons.bookmark_border),
      tooltip: L10n.t(context, 'profile.detail.savedSave'),
      onPressed: () async {
        final match = ref
            .read(chatProvider.notifier)
            .findOrCreateMatch(profile.id);
        if (match == null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'qr.limitBody')),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }
        ref
            .read(chatProvider.notifier)
            .updatePartner(match.id, profile);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tf(
                context, 'profile.detail.savedDone', {'name': profile.name})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }
}
