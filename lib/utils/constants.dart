/// App-weite Konstanten (Schlüssel, Defaults).
class AppConstants {
  AppConstants._();

  /// SharedPreferences-Schlüssel.
  static const String prefsSettingsKey = 'app_settings';
  static const String prefsProfileKey = 'user_profile';
  static const String prefsAuthKey = 'auth_user_id';
  static const String prefsCredentialsKey = 'auth_credentials';
  static const String prefsLikesKey = 'liked_profile_ids';
  static const String prefsGenderPreferenceKey = 'user_gender_preference';

  /// Fallback-ID für den Demo-Modus (kein Backend).
  static const String _demoUserId = 'me';

  /// Liefert die ID des aktuell eingeloggten Nutzers.
  ///
  /// Gibt die Supabase-User-ID zurück, wenn eine Session aktiv ist,
  /// sonst die Demo-ID `'me'` für den lokalen Modus.
  static String get currentUserId {
    try {
      // ignore: avoid_dynamic_calls
      final uid = _supabaseUserIdGetter?.call();
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {}
    return _demoUserId;
  }

  /// Wird in main.dart gesetzt, um die Supabase-User-ID abzurufen,
  /// ohne hier eine direkte Abhängigkeit zu erzeugen.
  static String? Function()? _supabaseUserIdGetter;

  /// Registriert den Getter für die Supabase-User-ID (Aufruf in main.dart).
  static void registerUserIdGetter(String? Function() getter) {
    _supabaseUserIdGetter = getter;
  }

  /// Expliziter Demo-Modus-Schalter.
  ///
  /// `--dart-define=DEMO_MODE=true` aktiviert den lokale Mock-Auth im Debug-Build.
  /// `--dart-define=DEMO_MODE=false` deaktiviert ihn explizit.
  /// Ohne Angabe wird im Debug-Modus auf die URL-Heuristik zurückgegriffen.
  static const String _demoModeRaw = String.fromEnvironment(
    'DEMO_MODE',
    defaultValue: 'auto',
  );

  static bool get demoModeExplicitTrue => _demoModeRaw.toLowerCase() == 'true';
  static bool get demoModeExplicitFalse => _demoModeRaw.toLowerCase() == 'false';

  /// ID des Admin-Accounts (via --dart-define=ADMIN_UUID=... beim Build).
  ///
  /// Wird beim Build gesetzt: `flutter build --dart-define=ADMIN_UUID=<echte-uuid>`.
  /// Ist der Parameter nicht gesetzt, bleibt der Wert leer → Admin-Funktionen
  /// sind deaktiviert (fail-safe: niemand kann Admin werden).
  /// Der Zugang erfolgt über versteckten Long-Press im Profil auf den Namen.
  static final String adminUserId = const String.fromEnvironment(
    'ADMIN_UUID',
    defaultValue: '',
  );

  /// Standard-Interessen zur schnellen Auswahl beim Profil.
  static const List<String> presetInterests = [
    'Sport', 'Musik', 'Reisen', 'Kochen', 'Filme', 'Gaming',
    'Kunst', 'Lesen', 'Fotografie', 'Tiere', 'Fitness', 'Natur',
    'Technologie', 'Mode', 'Tanzen', 'Yoga', 'Wandern', 'Kaffee',
    'Party', 'Nachhaltigkeit', 'Theater', 'Schreiben', 'Motorrad',
    'Klettern', 'Volunteering',
  ];

  /// Maximale Distanz (km) für den Entfernungsfilter (Slider-Obergrenze).
  static const int maxDistanceKm = 100;

  /// Standard-Distanz (km) für den Entfernungsfilter.
  static const int defaultDistanceKm = 50;

  // ===========================================================================
  // Build-Zeit-Konfiguration (via --dart-define)
  // ===========================================================================

  /// Hugging Face API-Token für NSFW-Moderation.
  /// Setzen via: flutter run --dart-define=HF_API_TOKEN=hf_xxx...
  /// Ohne Token wird Moderation deaktiviert (fail-safe: Fotos werden
  /// durchgelassen, aber im Admin-Screen markiert).
  static final String hfApiToken = const String.fromEnvironment(
    'HF_API_TOKEN',
    defaultValue: '',
  );

  /// Optional: eigener Hugging Face Inference-Endpunkt (z. B. EU-Region
  /// oder selbstgehostet). Standard bleibt der globale HF-Endpunkt.
  static const String hfInferenceUrl = String.fromEnvironment(
    'HF_INFERENCE_URL',
    defaultValue: 'https://api-inference.huggingface.co/models/Falconsai/nsfw_image_detection',
  );

  /// Optionale TURN-Server-Konfiguration für WebRTC.
  /// Ohne TURN funktioniert P2P hinter restrictiven NATs nicht zuverlässig.
  static const String turnServerUrl = String.fromEnvironment('TURN_SERVER_URL');
  static const String turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const String turnCredential = String.fromEnvironment('TURN_CREDENTIAL');
}
