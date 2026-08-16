import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/gender.dart';
import 'package:wisp/services/local_storage.dart';

/// Filter-Modus für die Entfernungs-Suche.
enum DistanceFilterMode {
  /// Entfernung in Kilometern (Slider).
  distanceKm,

  /// Bundesland (Dropdown).
  state,

  /// Ganz Deutschland (keine geografische Einschränkung).
  germany,
}

extension DistanceFilterModeLabel on DistanceFilterMode {
  String get label {
    switch (this) {
      case DistanceFilterMode.distanceKm:
        return 'Entfernung (km)';
      case DistanceFilterMode.state:
        return 'Bundesland';
      case DistanceFilterMode.germany:
        return 'Ganz Deutschland';
    }
  }
}

/// Nutzer-Präferenzen für Filter und Suche.
class UserPreferences {
  const UserPreferences({
    required this.genderPreferences,
    required this.distanceFilterMode,
    required this.maxDistanceKm,
    required this.preferredState,
    this.location,
    this.relationshipType,
  });

  /// Mehrfachauswahl der Geschlechts-Präferenz (Werte aus [Gender.value]).
  ///
  /// Alle sechs Geschlechter = funktional identisch mit der "Alle"-Option.
  /// Es ist immer mindestens ein Eintrag enthalten (UI verhindert Leermenge).
  final List<String> genderPreferences;
  final DistanceFilterMode distanceFilterMode;
  final int maxDistanceKm;
  final String? preferredState;
  final String? location;
  final RelationshipType? relationshipType;

  /// Erzeugt eine Kopie mit geänderten Feldern.
  UserPreferences copyWith({
    List<String>? genderPreferences,
    DistanceFilterMode? distanceFilterMode,
    int? maxDistanceKm,
    String? preferredState,
    String? location,
    RelationshipType? relationshipType,
    bool clearLocation = false,
  }) {
    return UserPreferences(
      genderPreferences: genderPreferences ?? this.genderPreferences,
      distanceFilterMode: distanceFilterMode ?? this.distanceFilterMode,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      preferredState: preferredState ?? this.preferredState,
      location: clearLocation ? null : (location ?? this.location),
      relationshipType: relationshipType ?? this.relationshipType,
    );
  }

  /// Serialisierung zu JSON.
  Map<String, dynamic> toJson() => {
        'genderPreferences': genderPreferences,
        'distanceFilterMode': distanceFilterMode.name,
        'maxDistanceKm': maxDistanceKm,
        'preferredState': preferredState,
        'location': location,
        'relationshipType': relationshipType?.value,
      };

  /// Deserialisierung aus JSON.
  ///
  /// Migriert das alte Format (einzelner String 'genderPreference')
  /// automatisch in die neue Liste: 'all'/leer -> alle Geschlechter,
  /// einzelner Wert -> Liste mit einem Eintrag.
  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      genderPreferences: _parseGenderPreferences(json),
      distanceFilterMode: DistanceFilterMode.values.byName(
        json['distanceFilterMode'] as String? ?? 'distanceKm',
      ),
      maxDistanceKm: json['maxDistanceKm'] as int? ?? 100,
      preferredState: json['preferredState'] as String?,
      location: json['location'] as String?,
      relationshipType: RelationshipType.values.byName(
        json['relationshipType'] as String? ?? 'open',
      ),
    );
  }

  static List<String> _parseGenderPreferences(Map<String, dynamic> json) {
    final raw = json['genderPreferences'];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    // Legacy-Format: einzelner String.
    final legacy = json['genderPreference'] as String?;
    if (legacy == null || legacy.isEmpty || legacy == 'all') {
      return List.of(kAllGenderValues);
    }
    return [legacy];
  }

  /// Standardwerte: KEINE Geschlechts-Präferenz ausgewählt
  /// (leer = kein Filter; "Alle" ist eine explizite, abwählbare Auswahl).
  factory UserPreferences.defaults() => const UserPreferences(
        genderPreferences: [],
        distanceFilterMode: DistanceFilterMode.distanceKm,
        maxDistanceKm: 100,
        preferredState: null,
        location: null,
        relationshipType: RelationshipType.open,
      );
}

/// StateNotifier für Nutzerpräferenzen.
class UserPreferencesNotifier extends StateNotifier<UserPreferences> {
  UserPreferencesNotifier(this._storage) : super(UserPreferences.defaults()) {
    _load();
  }

  final LocalStorage _storage;

  static const _prefsKey = 'user_preferences';

  Future<void> _load() async {
    final raw = await _storage.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        state = UserPreferences.fromJson(map);
      } catch (_) {
        // Bei korrupten Daten: Defaults beibehalten.
      }
    }
  }

  Future<void> _persist() async {
    await _storage.saveString(_prefsKey, jsonEncode(state.toJson()));
  }

  /// Setzt die komplette Präferenz-Liste (auch leer = kein Filter).
  Future<void> setGenderPreferences(List<String> values) async {
    state = state.copyWith(genderPreferences: values);
    await _persist();
  }

  /// Schaltet ein einzelnes Geschlecht um.
  ///
  /// Eine LEERE Auswahl ist erlaubt (kein Filter); es gibt kein
  /// Mindest-Eins-Mehr.
  Future<void> toggleGenderPreference(String value) async {
    final current = List<String>.from(state.genderPreferences);
    if (current.contains(value)) {
      current.remove(value);
    } else {
      current.add(value);
    }
    state = state.copyWith(genderPreferences: current);
    await _persist();
  }

  /// "Alle"-Kurzform: alle Geschlechter aktivieren.
  Future<void> selectAllGenders() async {
    state = state.copyWith(genderPreferences: List.of(kAllGenderValues));
    await _persist();
  }

  /// Hebt die Auswahl komplett auf (nichts ausgewählt = kein Filter).
  Future<void> clearGenders() async {
    state = state.copyWith(genderPreferences: const []);
    await _persist();
  }

  /// Setzt alle Präferenzen auf die Standardwerte zurück
  /// (z. B. nach Account-Löschung).
  Future<void> resetToDefaults() async {
    state = UserPreferences.defaults();
    await _persist();
  }

  Future<void> setDistanceFilterMode(DistanceFilterMode mode) async {
    state = state.copyWith(distanceFilterMode: mode);
    await _persist();
  }

  Future<void> setMaxDistanceKm(int km) async {
    state = state.copyWith(maxDistanceKm: km);
    await _persist();
  }

  Future<void> setPreferredState(String? stateCode) async {
    state = state.copyWith(preferredState: stateCode);
    await _persist();
  }

  Future<void> setLocation(String? location) async {
    state = state.copyWith(location: location);
    await _persist();
  }

  Future<void> setRelationshipType(RelationshipType? type) async {
    state = state.copyWith(relationshipType: type);
    await _persist();
  }
}

/// Provider für die Nutzerpräferenzen.
final userPreferencesProvider =
    StateNotifierProvider<UserPreferencesNotifier, UserPreferences>((ref) {
  final storage = ref.watch(localStorageProvider);
  return UserPreferencesNotifier(storage);
});
