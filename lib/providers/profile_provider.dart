import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/user_profile.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/utils/constants.dart';

/// Verwaltet das eigene Nutzerprofil und persistiert es lokal.
class ProfileNotifier extends StateNotifier<UserProfile> {
  ProfileNotifier(this._storage)
      : super(
          UserProfile(
            id: AppConstants.currentUserId,
            name: '',
            birthDate: null,
            bio: '',
          ),
        ) {
    _load();
  }

  final LocalStorage _storage;

  Future<void> _load() async {
    final raw = await _storage.getString(AppConstants.prefsProfileKey);
    if (raw != null) {
      try {
        state = UserProfile.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('[ProfileNotifier] Korrupte Profil-Daten erkannt: $e');
        // Korrupte Daten verwerfen – Nutzer muss Profil neu einrichten.
        await _storage.remove(AppConstants.prefsProfileKey);
        state = UserProfile(id: AppConstants.currentUserId, name: '', bio: '');
      }
    }
  }

  Future<void> _persist() async {
    await _storage.saveString(
      AppConstants.prefsProfileKey,
      jsonEncode(state.toJson()),
    );
  }

  /// überschreibt das Profil (z. B. nach Registrierung).
  Future<void> setProfile(UserProfile profile) async {
    state = profile;
    await _persist();
  }

  /// Aktualisiert einzelne Felder.
  Future<void> update({
    String? name,
    DateTime? birthDate,
    String? bio,
    List<String>? interests,
    List<String>? photos,
    String? city,
    String? stateStr,
    String? country,
    String? gender,
    String? personalityResult,
    String? personalityType,
    double? locationLat,
    double? locationLng,
    String? introText,
    String? introAudioPath,
    bool clearIntroAudio = false,
  }) async {
    state = state.copyWith(
      name: name,
      birthDate: birthDate,
      bio: bio,
      interests: interests,
      photos: photos,
      city: city,
      state: stateStr,
      country: country,
      gender: gender,
      personalityResult: personalityResult,
      personalityType: personalityType,
      locationLat: locationLat,
      locationLng: locationLng,
      introText: introText,
      introAudioPath: introAudioPath,
      clearIntroAudio: clearIntroAudio,
    );
    await _persist();
  }

  /// Fügt ein Interesse hinzu/entfernt es (Toggle).
  Future<void> toggleInterest(String interest) async {
    final set = {...state.interests};
    if (set.contains(interest)) {
      set.remove(interest);
    } else {
      set.add(interest);
    }
    state = state.copyWith(interests: set.toList());
    await _persist();
  }

  /// Fügt ein Foto (Pfad/URL) hinzu.
  Future<void> addPhoto(String path) async {
    state = state.copyWith(photos: [...state.photos, path]);
    await _persist();
  }

  /// Entfernt ein Foto an Index.
  Future<void> removePhotoAt(int index) async {
    final list = [...state.photos]..removeAt(index);
    state = state.copyWith(photos: list);
    await _persist();
  }

  /// Setzt das Profil auf einen leeren Zustand zurück
  /// (z. B. nach Account-Löschung – keine Alt-Daten im neuen Account).
  Future<void> resetToDefaults() async {
    state = UserProfile(id: AppConstants.currentUserId, name: '', bio: '');
    await _storage.remove(AppConstants.prefsProfileKey);
  }
}

/// Provider für das eigene Profil.
final profileProvider =
    StateNotifierProvider<ProfileNotifier, UserProfile>((ref) {
  final storage = ref.watch(localStorageProvider);
  return ProfileNotifier(storage);
});

