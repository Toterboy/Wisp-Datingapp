import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/services/api_auth_service.dart';
import 'package:wisp/services/api_client.dart';
import 'package:wisp/services/app_auth_service.dart';
import 'package:wisp/services/auth_service.dart';
import 'package:wisp/services/encryption_service.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/secure_storage.dart';
import 'package:wisp/services/supabase_auth_service.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Verwaltet den Auth-Status. Unterstützt drei Modi:
/// 1. Demo-Modus (kein Backend)
/// 2. Supabase Auth (Supabase RLS-Datenbank)
/// 3. Eigenes API-Backend (Signaling-Server + SQLite)
class AuthNotifier extends StateNotifier<AsyncValue<bool>> {
  AuthNotifier(this._auth, this._profileNotifier, this._ref)
      : super(const AsyncValue.loading()) {
    _restore();
    _listenToSupabaseAuth();
  }

  final AppAuthService _auth;
  final ProfileNotifier _profileNotifier;
  final Ref _ref;

  StreamSubscription<AuthState>? _authStateSub;

  /// Hält den Auth-Status synchron zu Supabase Auth.
  ///
  /// Verwirft Supabase die Session selbst (Refresh-Token invalide, Nutzer
  /// serverseitig gelöscht, Session aus einem anderen Projekt), bleibt der
  /// Status sonst auf "eingeloggt" kleben – der Nutzer landet dann ohne
  /// Session im E-Mail-Bestätigungs-Screen und hängt fest.
  void _listenToSupabaseAuth() {
    if (!SupabaseService.isInitialized) return;
    _authStateSub = SupabaseService.client.auth.onAuthStateChange.listen(
      (authState) {
        if (authState.event == AuthChangeEvent.signedOut) {
          state = const AsyncValue.data(false);
        }
      },
    );
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final loggedIn = await _auth.restoreSession();
      state = AsyncValue.data(loggedIn);
      if (loggedIn) {
        // Profil (Geburtsdatum/Alter!) und Setup-Flags vom Server nachladen.
        unawaited(_syncFromServer());
      }
    } catch (e, st) {
      // Fail-Safe gegen Deadlock beim Start: Bleibt der Zustand "loading",
      // würde der Router nie weiterleiten und die App hinge auf dem
      // Lade-Screen fest. Bei Fehler daher als "nicht eingeloggt"
      // fortfahren -> Nutzer landet auf Welcome/Login.
      debugPrint('[AuthNotifier] restoreSession fehlgeschlagen: $e');
      debugPrint('[AuthNotifier] StackTrace: $st');
      state = AsyncValue.error(e, st);
    }
  }

  /// Lädt Profil + Setup-Flags vom Server (nach Login/Session-Restore).
  ///
  /// Ohne diese Synchronisierung fehlt nach der Anmeldung das Profil
  /// (u. a. das Geburtsdatum -> falsche Alters-Clamps in der Einrichtung)
  /// und die Einrichtung würde nach Neuinstallation erneut erscheinen.
  Future<void> _syncFromServer() async {
    try {
      if (!SupabaseService.isInitialized) return;
      // Ohne Session (z. B. direkt nach der Registrierung, bevor die
      // E-Mail bestätigt ist) gibt es nichts zu prüfen.
      if (SupabaseService.currentUser == null) return;
      final database = SupabaseDatabaseService(SupabaseService.client);

      // FCM-Token-Registrierung NIE den kritischen Sync-Pfad blockieren
      // lassen (getToken kann auf Geräten ohne Google-Dienste hängen).
      unawaited(_syncFcmToken());

      // Profil laden. Ein Timeout/Netzfehler wirft und behält die Session
      // (kein fälschlicher Logout) – nur ein SAUBERES "keine Zeile" bei
      // vorhandener Session bedeutet: Account wurde serverseitig gelöscht.
      // Kurzes Timeout, damit der Router beim Start nicht lange auf dem
      // Lade-Screen hängt.
      final profile = await database
          .fetchOwnProfile()
          .timeout(const Duration(seconds: 3));
      if (profile == null) {
        debugPrint(
          '[AuthNotifier] Profil fehlt trotz Session – Account wurde '
          'serverseitig gelöscht. Lokale Session und Daten werden verworfen.',
        );
        await _auth.logout();
        await _ref.read(settingsProvider.notifier).resetToDefaults();
        await _ref.read(userPreferencesProvider.notifier).resetToDefaults();
        await _ref.read(profileProvider.notifier).resetToDefaults();
        _ref.read(pendingVerificationEmailProvider.notifier).state = null;
        _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
        state = const AsyncValue.data(false);
        return;
      }
      _profileNotifier.setProfile(profile);

      final flags = await database
          .fetchSetupFlags()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (flags != null) {
        await _ref.read(settingsProvider.notifier).syncSetupFlagsFromServer(
              oneTimeSettingsCompleted:
                  flags['one_time_settings_completed'] == true,
              communityGuidelinesAccepted:
                  flags['community_guidelines_accepted'] == true,
              personalityTestCompleted:
                  flags['personality_test_completed'] == true,
            );
      }
    } catch (e) {
      debugPrint('[AuthNotifier] Server-Sync fehlgeschlagen: $e');
    } finally {
      // Router freigeben: Setup-Flags sind geladen (oder der Sync ist
      // gescheitert - dann gilt der lokale Stand).
      _ref.read(serverSyncDoneProvider.notifier).state = true;
    }
  }

  /// Registriert das aktuelle FCM-Geräte-Token in der profiles-Tabelle,
  /// damit die Edge Function notify-user Push-Benachrichtigungen an
  /// dieses Gerät senden kann. Best effort – mit Timeout, damit
  /// getToken() (kann ohne Google-Dienste hängen) nie blockiert.
  Future<void> _syncFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (token == null) return;
      await SupabaseDatabaseService(SupabaseService.client)
          .updateOwnProfile({'fcm_token': token});
    } catch (e) {
      debugPrint('[AuthNotifier] FCM-Token-Sync fehlgeschlagen: $e');
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    required DateTime birthDate,
    String? inviteCode,
  }) async {
    debugPrint('[AuthNotifier] register() aufgerufen: name=$name, email=$email, gender=$gender, inviteCode=$inviteCode');
    state = const AsyncValue.loading();
    try {
      // Standort für Fake-Account-Erkennung erfassen.
      double? lat, lng;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 5),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        // Standort nicht verfügbar – Registrierung trotzdem fortfahren.
        debugPrint('[AuthNotifier] Standort konnte nicht erfasst werden.');
      }

      final profile = await _auth.register(
        name: name,
        email: email,
        password: password,
        gender: gender,
        birthDate: birthDate,
        inviteCode: inviteCode,
        latitude: lat,
        longitude: lng,
      );
      debugPrint('[AuthNotifier] register() erfolgreich: userId=${profile.id}');
      // E-Mail für den Bestätigungs-Screen sichern. Bei aktivierter
      // E-Mail-Bestätigung liefert signUp KEINE Session (currentUser == null),
      // daher muss die Adresse aus dem Registrierungs-Formular kommen -
      // sonst schlägt "Bestätigungs-Mail erneut senden" fehl.
      _ref.read(pendingVerificationEmailProvider.notifier).state = email;
      // E-Mail + Passwort NUR IM SPEICHER für den stillen Auto-Login nach
      // der Bestätigung sichern (nie persistiert). Damit erkennt die App
      // die Bestätigung ohne Session und meldet den Nutzer automatisch an.
      _ref.read(pendingVerificationCredentialsProvider.notifier).state =
          (email: email, password: password);
      _profileNotifier.setProfile(profile);
      state = const AsyncValue.data(true);
      // Server-Sync auch NACH der Registrierung anstoßen: Er setzt
      // serverSyncDoneProvider und gibt damit den Router frei (sonst
      // bleibt die App auf dem Lade-Screen hängen). Zusätzlich wird das
      // FCM-Token registriert.
      unawaited(_syncFromServer());
    } catch (e, st) {
      debugPrint('[AuthNotifier] register() FEHLER: $e');
      debugPrint('[AuthNotifier] StackTrace: $st');
      state = AsyncValue.error(e, st);
      rethrow; // Fehler an den Aufrufer durchreichen, damit die UI ihn anzeigen kann
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    debugPrint('[AuthNotifier] login() aufgerufen: email=$email');
    state = const AsyncValue.loading();
    try {
      await _auth.login(email: email, password: password);
      debugPrint('[AuthNotifier] login erfolgreich');
      // Nach erfolgreichem Login sind die zwischengespeicherten
      // Registrierungs-Daten nicht mehr nötig.
      _ref.read(pendingVerificationEmailProvider.notifier).state = null;
      _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
      state = const AsyncValue.data(true);
      unawaited(_syncFromServer());
    } catch (e, st) {
      debugPrint('[AuthNotifier] login() FEHLER: $e');
      debugPrint('[AuthNotifier] StackTrace: $st');
      state = AsyncValue.error(e, st);
      rethrow; // Fehler an den Aufrufer durchreichen
    }
  }

  Future<void> logout() async {
    await _auth.logout();
    _ref.read(pendingVerificationEmailProvider.notifier).state = null;
    _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
    _ref.read(serverSyncDoneProvider.notifier).state = false;
    state = const AsyncValue.data(false);
  }

  /// Stiller Login für den Auto-Login nach der E-Mail-Bestätigung.
  ///
  /// Führt den Login durch, OHNE den öffentlichen Auth-Status auf
  /// loading/error zu setzen. Wichtiger Unterschied zu [login]: Ein
  /// fehlgeschlagener Versuch (E-Mail noch nicht bestätigt) würde sonst
  /// den Status auf AsyncError setzen, der Router würde den Nutzer als
  /// "ausgeloggt" behandeln und ihn vom Bestätigungs-Screen zum
  /// Login-Screen werfen. Nur bei ERFOLG wird der Status aktualisiert.
  Future<void> silentLogin({
    required String email,
    required String password,
  }) async {
    await _auth.login(email: email, password: password);
    _ref.read(pendingVerificationEmailProvider.notifier).state = null;
    _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
    state = const AsyncValue.data(true);
  }

  Future<void> deleteAccount() async {
    await _auth.deleteAccount();
    // Lokale Daten vollständig löschen: Nach einer Account-Löschung dürfen
    // keine Alt-Daten (Profil, Einstellungen, Präferenzen) in einen neuen
    // Account übergehen – auch DSGVO-relevant (Art. 17).
    _ref.read(pendingVerificationEmailProvider.notifier).state = null;
    _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
    await _ref.read(settingsProvider.notifier).resetToDefaults();
    await _ref.read(userPreferencesProvider.notifier).resetToDefaults();
    await _ref.read(profileProvider.notifier).resetToDefaults();
    state = const AsyncValue.data(false);
  }
}

/// Prüft, ob der Demo-Modus (lokaler Mock) aktiv ist.
///
/// Im Release-Modus ist der Demo-Modus IMMER deaktiviert.
/// Im Debug-Modus gilt:
///   - Mit --dart-define=DEMO_MODE=true ist er aktiv.
///   - Mit --dart-define=DEMO_MODE=false ist er inaktiv (fail-safe).
///   - Ohne Angabe wird auf die URL-Heuristik zurückgegriffen.
bool _isDemoMode() {
  if (kReleaseMode) return false;
  if (SupabaseService.isInitialized) return false;

  // Explizites Build-Time-Flag hat Vorrang.
  if (AppConstants.demoModeExplicitTrue) return true;
  if (AppConstants.demoModeExplicitFalse) return false;

  // Legacy-Fallback-Heuristik für Debug-Builds ohne explizites Flag.
  const baseUrl = ApiConfig.baseUrl;
  return baseUrl.contains('example.com') ||
      baseUrl.contains('localhost') ||
      baseUrl.isEmpty;
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<bool>>((ref) {
  final tokens = ref.watch(secureTokenStoreProvider);
  final encryption = ref.watch(encryptionServiceProvider);
  final storage = ref.watch(localStorageProvider);

  final AppAuthService auth;

  if (SupabaseService.isInitialized) {
    final database = SupabaseDatabaseService(SupabaseService.client);
    auth = SupabaseAuthService(
      SupabaseService.client,
      tokens,
      encryption,
      database,
    );
  } else if (_isDemoMode()) {
    final prefs = storage is SharedPreferencesStorage ? storage.raw : null;
    auth = AuthService(
      () async => prefs?.getString(AppConstants.prefsAuthKey),
      (String v) async => await prefs?.setString(AppConstants.prefsAuthKey, v),
      () async => prefs?.getString(AppConstants.prefsCredentialsKey),
      (String v) async => await prefs?.setString(AppConstants.prefsCredentialsKey, v),
    );
  } else {
    final api = ref.watch(apiClientProvider);
    auth = ApiAuthService(api, tokens, encryption);
  }

  return AuthNotifier(auth, ref.watch(profileProvider.notifier), ref);
});

/// E-Mail-Adresse aus der Registrierung für den Bestätigungs-Screen.
///
/// Nach signUp mit aktivierter E-Mail-Bestätigung existiert KEINE Session
/// (currentUser == null). Der Bestätigungs-Screen braucht die Adresse aber
/// für "Erneut senden" - daher wird sie hier zwischengespeichert.
final pendingVerificationEmailProvider = StateProvider<String?>((ref) => null);

/// E-Mail + Passwort der letzten Registrierung - NUR IM SPEICHER, nie
/// persistiert.
///
/// Der Bestätigungs-Screen versucht damit im Hintergrund einen stillen
/// Login. Solange die E-Mail unbestätigt ist, schlägt er fehl; nach der
/// Bestätigung baut er automatisch die Session auf und die App geht weiter.
/// Wird bei erfolgreichem Login/Logout geleert; App-Neustart löscht den
/// Wert ebenfalls (Speicher-only).
final pendingVerificationCredentialsProvider =
    StateProvider<({String email, String password})?>((ref) => null);

/// Zeigt an, ob der Server-Sync nach Login/Session-Restore abgeschlossen
/// ist (Profil + Setup-Flags). Der Router wartet darauf, damit nach einer
/// App-Neuinstallation die Einrichtung NICHT kurz aufblitzt, bevor die
/// serverseitigen Setup-Flags geladen sind.
final serverSyncDoneProvider = StateProvider<bool>((ref) => false);

/// Prüft, ob die E-Mail des aktuellen Supabase-Nutzers bestaetigt ist.
///
/// Pollt den Auth-Status alle 3 Sekunden, damit der Nutzer nach Klick auf
/// den Bestätigungslink in der E-Mail automatisch weiterkommt, ohne die
/// App neu starten zu müssen. Das Polling wird im Hintergrund pausiert,
/// um Akku und Daten zu schonen.
///
/// Liefert:
/// - `true`, wenn E-Mail bestaetigt ist
/// - `false`, wenn E-Mail noch nicht bestaetigt ist
/// - `null`, wenn kein Supabase-Modus aktiv ist oder keine Session existiert
class EmailConfirmedNotifier extends StateNotifier<bool?>
    with WidgetsBindingObserver {
  EmailConfirmedNotifier(this._ref) : super(null) {
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  final Ref _ref;
  Timer? _timer;

  void _startPolling() {
    _timer?.cancel();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Polling im Hintergrund pausieren, um Akku zu schonen.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopPolling();
    } else if (state == AppLifecycleState.resumed) {
      _startPolling();
    }
  }

  Future<void> _check() async {
    try {
      if (!SupabaseService.isInitialized) {
        if (state != null) state = null;
        return;
      }

      // WICHTIG: valueOrNull statt value verwenden – bei einem AsyncError
      // (z. B. fehlgeschlagener Auto-Login) würde .value die gespeicherte
      // Exception erneut werfen (Unhandled Exception im Polling-Timer).
      final auth = _ref.read(authProvider);
      final loggedIn = auth.valueOrNull ?? false;
      if (!loggedIn) {
        if (state != null) state = null;
        return;
      }

      final session = SupabaseService.client.auth.currentSession;
      final user = session?.user;
      final confirmed = user?.emailConfirmedAt != null;
      if (state != confirmed) {
        log('[EmailConfirmedNotifier] emailConfirmed=$confirmed');
        state = confirmed;
      }
      // Batterie/Netz schonen: Nach Bestätigung ist Polling unnötig.
      if (confirmed) {
        _stopPolling();
      }
    } catch (e) {
      log('[EmailConfirmedNotifier] Polling error: $e');
      // Bei Fehler aktuellen Zustand behalten, um Flackern zu vermeiden.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }
}

final emailConfirmedProvider =
    StateNotifierProvider<EmailConfirmedNotifier, bool?>((ref) {
  return EmailConfirmedNotifier(ref);
});



