import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/app_settings.dart';
import 'package:wisp/models/profile_visibility.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/utils/constants.dart';

/// StateNotifier, der die App-Einstellungen verwaltet und sicher persistiert.
///
/// Zuständig für: Blind Mode, Foto-Freigabe, Sichtbarkeit, Theme, Onboarding, Swipe-Modus.
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._storage, this._ref) : super(AppSettings.defaults()) {
    _load();
  }

  final LocalStorage _storage;
  final Ref _ref;

  /// Lädt die gespeicherten Einstellungen beim Start.
  Future<void> _load() async {
    try {
      final raw = await _storage.getString(AppConstants.prefsSettingsKey);
      if (raw != null) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          state = AppSettings.fromJson(map);
        } catch (_) {
          // Bei korrupten Daten: Defaults beibehalten.
        }
      }
    } finally {
      // Router benachrichtigen, dass die Settings geladen sind.
      // Der Router wartet beim Start auf diesen Zustand (zusätzlich zum
      // Auth-Status), bevor die initiale Route bestimmt wird - sonst
      // Race Condition zwischen Onboarding-Flag- und Auth-Check und der
      // "Konto erstellen"-Screen blitzt vor den Willkommensscreens auf.
      _ref.read(settingsLoadedProvider.notifier).state = true;
    }
  }

  Future<void> _persist() async {
    await _storage.saveString(
      AppConstants.prefsSettingsKey,
      jsonEncode(state.toJson()),
    );
  }

  /// Schaltet den Blind Mode um.
  Future<void> toggleBlindMode(bool value) async {
    state = state.copyWith(blindModeEnabled: value);
    await _persist();
  }

  /// Blendet den MFA-Einrichtungshinweis dauerhaft aus.
  Future<void> setMfaSetupDismissed(bool value) async {
    state = state.copyWith(mfaSetupDismissed: value);
    await _persist();
  }

  /// Legt fest, ob die eigenen Fotos erst nach Match sichtbar sind.
  Future<void> setRevealPhotosAfterMatch(bool value) async {
    state = state.copyWith(revealPhotosAfterMatch: value);
    await _persist();
  }

  /// Setzt die Profil-Sichtbarkeit (Privatsphäre).
  Future<void> setProfileVisibility(ProfileVisibility value) async {
    state = state.copyWith(profileVisibility: value);
    await _persist();
  }

  /// Setzt das Theme (null = System).
  Future<void> setDarkMode(bool? value) async {
    state = state.copyWith(useDarkMode: value);
    await _persist();
  }

  /// Setzt die maximale Distanz (km) für den Entfernungsfilter.
  Future<void> setMaxDistanceKm(int value) async {
    state = state.copyWith(maxDistanceKm: value);
    await _persist();
  }

  /// Setzt die bevorzugte Alterspanne (Jahre).
  Future<void> setAgeRange(int min, int max) async {
    state = state.copyWith(ageRangeMin: min, ageRangeMax: max);
    await _persist();
  }

  /// Markiert den Persönlichkeitstest als abgeschlossen.
  Future<void> completePersonalityTest() async {
    state = state.copyWith(personalityTestCompleted: true);
    await _persist();
  }

  /// Markiert das Onboarding als abgeschlossen.
  Future<void> completeOnboarding() async {
    state = state.copyWith(onboardingCompleted: true);
    await _persist();
  }

  /// Markiert die einmaligen Settings/Privacy nach Registrierung als abgeschlossen.
  Future<void> completeOneTimeSettings() async {
    state = state.copyWith(oneTimeSettingsCompleted: true);
    await _persist();
  }

  /// Markiert die Community-Richtlinien als akzeptiert.
  Future<void> acceptCommunityGuidelines() async {
    state = state.copyWith(communityGuidelinesAccepted: true);
    await _persist();
  }

  /// Markiert die Einführung (Willkommens-Screen) als gesehen, damit sie
  /// beim nächsten Start nicht erneut erscheint.
  Future<void> markIntroSeen() async {
    state = state.copyWith(introSeen: true);
    await _persist();
  }

  /// Markiert das Dating Hour Intro (Regeln + Erklärung) als gesehen.
  Future<void> markDatingHourIntroSeen() async {
    state = state.copyWith(datingHourIntroSeen: true);
    await _persist();
  }

  /// Dating Hour: Automatische Teilnahme am nächsten Event aktivieren
  /// bzw. deaktivieren (Abfrage nach Ende eines Events).
  Future<void> setDatingHourAutoJoin(bool value) async {
    state = state.copyWith(datingHourAutoJoin: value);
    await _persist();
  }

  /// Übernimmt die Setup-Flags vom Server (nach Login/Session-Restore).
  ///
  /// Der Server gewinnt bei "abgeschlossen" – so erscheint die Einrichtung
  /// nach einer App-Neuinstallation NICHT erneut, nur weil die lokale
  /// Speicherung fehlt. Lokal wird der Stand ebenfalls gespiegelt.
  Future<void> syncSetupFlagsFromServer({
    required bool oneTimeSettingsCompleted,
    required bool communityGuidelinesAccepted,
    required bool personalityTestCompleted,
  }) async {
    var changed = false;
    var next = state;
    if (oneTimeSettingsCompleted && !next.oneTimeSettingsCompleted) {
      next = next.copyWith(oneTimeSettingsCompleted: true);
      changed = true;
    }
    if (communityGuidelinesAccepted && !next.communityGuidelinesAccepted) {
      next = next.copyWith(communityGuidelinesAccepted: true);
      changed = true;
    }
    if (personalityTestCompleted && !next.personalityTestCompleted) {
      next = next.copyWith(personalityTestCompleted: true);
      changed = true;
    }
    if (changed) {
      state = next;
      await _persist();
    }
  }

  /// Aktiviert oder deaktiviert Benachrichtigungen.
  Future<void> setNotificationsEnabled(bool enabled) async {
    state = state.copyWith(notificationsEnabled: enabled);
    await _persist();
  }

  /// Einzel-Schalter: Benachrichtigung bei neuem Match.
  Future<void> setNotifyMatches(bool enabled) async {
    state = state.copyWith(notifyMatches: enabled);
    await _persist();
  }

  /// Einzel-Schalter: Benachrichtigung bei erhaltenem Like.
  Future<void> setNotifyLikes(bool enabled) async {
    state = state.copyWith(notifyLikes: enabled);
    await _persist();
  }

  /// Einzel-Schalter: Benachrichtigung bei neuer Chat-Nachricht.
  Future<void> setNotifyMessages(bool enabled) async {
    state = state.copyWith(notifyMessages: enabled);
    await _persist();
  }

  /// Einzel-Schalter: Erinnerung, wenn die Dating Hour gleich beginnt.
  Future<void> setNotifyDatingHour(bool enabled) async {
    state = state.copyWith(notifyDatingHour: enabled);
    await _persist();
  }

  /// Bilder im Chat standardmäßig verpixelt anzeigen?
  Future<void> setBlurChatImages(bool enabled) async {
    state = state.copyWith(blurChatImages: enabled);
    await _persist();
  }

  /// Farbschema wechseln (WispTheme-Name).
  Future<void> setThemeName(String name) async {
    state = state.copyWith(themeName: name);
    await _persist();
  }

  /// Setzt alle Einstellungen auf die Standardwerte zurück
  /// (z. B. nach Account-Löschung – keine Alt-Daten im neuen Account).
  Future<void> resetToDefaults() async {
    state = AppSettings.defaults();
    await _persist();
  }
}

/// Zeigt an, ob die Einstellungen aus dem Speicher geladen wurden.
///
/// Der Router wartet beim App-Start auf diesen Zustand (zusätzlich zum
/// Auth-Status), bevor die initiale Route bestimmt wird. Erst wenn beide
/// Checks abgeschlossen sind, wird weitergeleitet - so ist die
/// Screen-Reihenfolge beim Erststart garantiert (Willkommen vor Login).
final settingsLoadedProvider = StateProvider<bool>((ref) => false);

/// Provider für die App-Einstellungen.
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final storage = ref.watch(localStorageProvider);
  return SettingsNotifier(storage, ref);
});
