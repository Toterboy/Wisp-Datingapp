import 'package:wisp/models/profile_visibility.dart';
import 'package:wisp/utils/constants.dart';

/// App-Einstellungen inkl. Blind-Mode und Privatsphäre-Optionen.
///
/// Diese Klasse ist die "Single Source of Truth" für Nutzerpräferenzen und
/// wird sicher lokal (shared_preferences) gespeichert.
class AppSettings {
  /// Blind Mode: Fotos werden erst nach einem Match angezeigt.
  final bool blindModeEnabled;

  /// Eigene Fotos erst nach Match freigeben.
  final bool revealPhotosAfterMatch;

  /// Wer darf das eigene Profil sehen?
  final ProfileVisibility profileVisibility;

  /// Dark Mode erzwungen? (true = dunkel, false = hell, null = System)
  final bool? useDarkMode;

  /// Onboarding bereits gesehen?
  final bool onboardingCompleted;

  /// Maximale Distanz (km) für den Entfernungsfilter.
  final int maxDistanceKm;

  /// Untere Grenze der bevorzugten Alterspanne (Jahre).
  final int ageRangeMin;

  /// Obere Grenze der bevorzugten Alterspanne (Jahre).
  final int ageRangeMax;

  /// Persönlichkeitstest abgeschlossen?
  final bool personalityTestCompleted;

  /// Einmalige Settings/Privacy nach Registrierung abgeschlossen?
  final bool oneTimeSettingsCompleted;

  /// Community Richtlinien akzeptiert?
  final bool communityGuidelinesAccepted;

  /// Einführung (Willkommens-Screen) bereits gesehen?
  /// Wenn true, wird der Willkommens-Screen nicht erneut gezeigt.
  final bool introSeen;

  /// Benachrichtigungen aktiv?
  final bool notificationsEnabled;

  /// Einzel-Schalter: Benachrichtigung bei neuem Match.
  final bool notifyMatches;

  /// Einzel-Schalter: Benachrichtigung bei erhaltenem Like.
  final bool notifyLikes;

  /// Einzel-Schalter: Benachrichtigung bei neuer Chat-Nachricht.
  final bool notifyMessages;

  /// Einzel-Schalter: Erinnerung, wenn die Dating Hour gleich beginnt.
  final bool notifyDatingHour;

  /// Dating Hour Intro (Regeln + Erklärung) bereits gesehen?
  final bool datingHourIntroSeen;

  const AppSettings({
    this.blindModeEnabled = true,
    this.revealPhotosAfterMatch = true,
    this.profileVisibility = ProfileVisibility.everyone,
    this.useDarkMode,
    this.onboardingCompleted = true,
    this.maxDistanceKm = AppConstants.defaultDistanceKm,
    this.ageRangeMin = 16,
    this.ageRangeMax = 99,
    this.personalityTestCompleted = false,
    this.oneTimeSettingsCompleted = false,
    this.communityGuidelinesAccepted = false,
    this.introSeen = false,
    this.notificationsEnabled = true,
    this.notifyMatches = true,
    this.notifyLikes = true,
    this.notifyMessages = true,
    this.notifyDatingHour = true,
    this.datingHourIntroSeen = false,
  });

  /// Standard-Einstellungen für einen neuen Nutzer.
  factory AppSettings.defaults() => const AppSettings();

  /// Erzeugt Einstellungen aus einem JSON-Map.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      blindModeEnabled: json['blindModeEnabled'] as bool? ?? true,
      revealPhotosAfterMatch: json['revealPhotosAfterMatch'] as bool? ?? true,
      profileVisibility:
          ProfileVisibility.fromValue(json['profileVisibility'] as String?),
      useDarkMode: json['useDarkMode'] as bool?,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? true,
      maxDistanceKm: json['maxDistanceKm'] as int? ?? AppConstants.defaultDistanceKm,
      ageRangeMin: json['ageRangeMin'] as int? ?? 16,
      ageRangeMax: json['ageRangeMax'] as int? ?? 99,
      personalityTestCompleted:
          json['personalityTestCompleted'] as bool? ?? false,
      oneTimeSettingsCompleted:
          json['oneTimeSettingsCompleted'] as bool? ?? false,
      communityGuidelinesAccepted:
          json['communityGuidelinesAccepted'] as bool? ?? false,
      introSeen: json['introSeen'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      notifyMatches: json['notifyMatches'] as bool? ?? true,
      notifyLikes: json['notifyLikes'] as bool? ?? true,
      notifyMessages: json['notifyMessages'] as bool? ?? true,
      notifyDatingHour: json['notifyDatingHour'] as bool? ?? true,
      datingHourIntroSeen: json['datingHourIntroSeen'] as bool? ?? false,
    );
  }

  /// Wandelt die Einstellungen in ein JSON-Map um.
  Map<String, dynamic> toJson() => {
        'blindModeEnabled': blindModeEnabled,
        'revealPhotosAfterMatch': revealPhotosAfterMatch,
        'profileVisibility': profileVisibility.value,
        'useDarkMode': useDarkMode,
        'onboardingCompleted': onboardingCompleted,
        'maxDistanceKm': maxDistanceKm,
        'ageRangeMin': ageRangeMin,
        'ageRangeMax': ageRangeMax,
        'personalityTestCompleted': personalityTestCompleted,
        'oneTimeSettingsCompleted': oneTimeSettingsCompleted,
        'communityGuidelinesAccepted': communityGuidelinesAccepted,
        'introSeen': introSeen,
        'notificationsEnabled': notificationsEnabled,
        'notifyMatches': notifyMatches,
        'notifyLikes': notifyLikes,
        'notifyMessages': notifyMessages,
        'notifyDatingHour': notifyDatingHour,
        'datingHourIntroSeen': datingHourIntroSeen,
      };

  /// Immutabele Kopie mit veränderten Werten.
  AppSettings copyWith({
    bool? blindModeEnabled,
    bool? revealPhotosAfterMatch,
    ProfileVisibility? profileVisibility,
    bool? useDarkMode,
    bool? onboardingCompleted,
    int? maxDistanceKm,
    int? ageRangeMin,
    int? ageRangeMax,
    bool? personalityTestCompleted,
    bool? oneTimeSettingsCompleted,
    bool? communityGuidelinesAccepted,
    bool? introSeen,
    bool? notificationsEnabled,
    bool? notifyMatches,
    bool? notifyLikes,
    bool? notifyMessages,
    bool? notifyDatingHour,
    bool? datingHourIntroSeen,
  }) {
    return AppSettings(
      blindModeEnabled: blindModeEnabled ?? this.blindModeEnabled,
      revealPhotosAfterMatch:
          revealPhotosAfterMatch ?? this.revealPhotosAfterMatch,
      profileVisibility: profileVisibility ?? this.profileVisibility,
      useDarkMode: useDarkMode ?? this.useDarkMode,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      ageRangeMin: ageRangeMin ?? this.ageRangeMin,
      ageRangeMax: ageRangeMax ?? this.ageRangeMax,
      personalityTestCompleted:
          personalityTestCompleted ?? this.personalityTestCompleted,
      oneTimeSettingsCompleted:
          oneTimeSettingsCompleted ?? this.oneTimeSettingsCompleted,
      communityGuidelinesAccepted:
          communityGuidelinesAccepted ?? this.communityGuidelinesAccepted,
      introSeen: introSeen ?? this.introSeen,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notifyMatches: notifyMatches ?? this.notifyMatches,
      notifyLikes: notifyLikes ?? this.notifyLikes,
      notifyMessages: notifyMessages ?? this.notifyMessages,
      notifyDatingHour: notifyDatingHour ?? this.notifyDatingHour,
      datingHourIntroSeen: datingHourIntroSeen ?? this.datingHourIntroSeen,
    );
  }
}