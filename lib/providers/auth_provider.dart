import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/services/app_auth_service.dart';
import 'package:wisp/services/auth_service.dart';
import 'package:wisp/services/encryption_service.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/mfa_service.dart';
import 'package:wisp/services/prekey_service.dart';
import 'package:wisp/services/secure_location_storage.dart';
import 'package:wisp/services/secure_storage.dart';
import 'package:wisp/services/supabase_auth_service.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/verification_service.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/utils/demo_mode.dart';
import 'package:wisp/utils/temp_cleanup.dart';
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

  /// Nach dem allerersten _syncFromServer Aufruf true.
  /// Selbstheilung laeuft NUR danach – so werden lokale Restwerte
  /// (von einem frueheren Test/Install) nicht faelschlich zum Server
  /// gepusht und die Einrichtung bei der ersten Registrierung nicht
  /// uebersprungen.
  bool _initialServerSyncDone = false;

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
        final event = authState.event;
        if (event == AuthChangeEvent.signedOut) {
          state = const AsyncValue.data(false);
        } else if (event == AuthChangeEvent.passwordRecovery) {
          // Passwort-Reset (Recovery-Deep-Link aus der E-Mail, von
          // getSessionFromUrl via detectSessionInUriPredicate verarbeitet):
          // Der Router erzwingt jetzt den Reset-Screen, bis das neue
          // Passwort gesetzt ist (updateUser).
          _ref.read(passwordRecoveryPendingProvider.notifier).state = true;
          if (!state.hasValue || state.value != true) {
            state = const AsyncValue.data(true);
            unawaited(_syncFromServer());
          }
        } else if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.initialSession) {
          // Passkey-Login (oder andere stille Anmeldung) meldet sich hier
          // an, ohne dass login()/register() den State gesetzt hat.
          if (!state.hasValue || state.value != true) {
            state = const AsyncValue.data(true);
            unawaited(_syncFromServer());
          }
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
      // Globale Sicherheits-Wache: Falls restoreSession() (z. B. im
      // API-Backend-Modus bei nicht erreichbarem Server) HÄNGT und nie
      // zurückkehrt, würde der Router ewig auf dem Lade-Screen bleiben.
      // Nach dem Timeout wird sicher als "nicht eingeloggt" fortgefahren.
      final loggedIn = await _auth
          .restoreSession()
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      state = AsyncValue.data(loggedIn);
      if (loggedIn) {
        // „Angemeldet bleiben"-Wunsch respektieren (Default: AN). Wenn der
        // Nutzer die Option im Login bewusst deaktiviert hat, wird die
        // Session beim Start still verworfen -> Login-Screen.
        final keepLoggedIn =
            await _ref.read(localStorageProvider).getBool('keep_logged_in') ??
                true;
        if (!keepLoggedIn) {
          await _auth.logout();
          state = const AsyncValue.data(false);
          return;
        }
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
      state = const AsyncValue.data(false);
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

      // Audit H-7/E-3: Eigenes PreKey-Bundle veröffentlichen, falls noch
      // keines existiert (sonst schlägt jeder E2E-Session-Aufbau durch
      // Dritte fehl). Hintergrund, blockiert den Sync nicht.
      unawaited(
        _ref.read(preKeyServiceProvider).ensureOwnBundlePublished(),
      );

      // MFA-Status UNABHÄNGIG vom Profil-Fetch laden (eigener try-Block):
      // Schlägt der Profil-Fetch per Timeout fehl, darf die App trotzdem
      // wissen, ob 2FA aktiv ist - sonst zeigt sie nach einem Update fälsch-
      // lich "nicht eingerichtet".
      try {
        _ref.read(mfaStatusProvider.notifier).state =
            await MfaService(SupabaseService.client).loadStatus().timeout(
                  const Duration(seconds: 5),
                  onTimeout: () => const MfaStatus.initial(),
                );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[AuthNotifier] MFA-Status konnte nicht geladen werden: $e');
        }
      }

      // Profil laden. Ein Timeout/Netzfehler wirft und behält die Session
      // (kein fälschlicher Logout) – nur ein SAUBERES "keine Zeile" bei
      // vorhandener Session bedeutet: Account wurde serverseitig gelöscht.
      // Kurzes Timeout, damit der Router beim Start nicht lange auf dem
      // Lade-Screen hängt.
      final profile = await database
          .fetchOwnProfile()
          .timeout(const Duration(seconds: 3));
      if (profile == null) {
        // Nur die SESSION verwerfen - lokale Daten (Profil, Einstellungen,
        // Praeferenzen) bleiben als Cache erhalten. Vorher wurden sie hier
        // komplett geloescht, was bei einem falsch-negativ (z. B. RLS-
        // Strohfeuer) den Nutzer alles neu eingeben liess. Nach erneutem
        // Login liefert der Server das Profil ohnehin wieder.
        debugPrint(
          '[AuthNotifier] Profil fehlt trotz Session - Session wird '
          'verworfen (lokale Daten bleiben erhalten).',
        );
        await _auth.logout();
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

        // Selbstheilung (Fix "Einrichtung erscheint erneut"): Lokale
        // "erledigt"-Flags, die dem Server fehlen (z. B. weil das Speichern
        // bei der Einrichtung still fehlschlug), werden hier nachgezogen.
        // NUR nach dem ersten Sync – so werden lokale Restwerte (z. B. von
        // einem frueheren Test/Install) nicht zum Server gepusht und die
        // Einrichtung bei der allerersten Registrierung nicht uebersprungen.
        if (_initialServerSyncDone) {
          final s = _ref.read(settingsProvider);
          if ((s.oneTimeSettingsCompleted &&
                  flags['one_time_settings_completed'] != true) ||
              (s.communityGuidelinesAccepted &&
                  flags['community_guidelines_accepted'] != true)) {
            try {
              await database.updateOwnProfile({
                'one_time_settings_completed': s.oneTimeSettingsCompleted,
                'community_guidelines_accepted': s.communityGuidelinesAccepted,
              });
             } catch (e) {
              debugPrint('[AuthNotifier] Setup-Flags-Nachzug fehlgeschlagen: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AuthNotifier] Server-Sync fehlgeschlagen: $e');
    } finally {
      // Router freigeben: Setup-Flags sind geladen (oder der Sync ist
      // gescheitert - dann gilt der lokale Stand).
      _ref.read(serverSyncDoneProvider.notifier).state = true;
      // Ersten Sync abschliessen: Ab jetzt darf die Selbstheilung
      // lokale Flags zum Server nachziehen (siehe oben).
      _initialServerSyncDone = true;
    }
  }

  /// Registriert das aktuelle FCM-Geräte-Token in der profiles-Tabelle,
  /// damit die Edge Function notify-user Push-Benachrichtigungen an
  /// dieses Gerät senden kann. Best effort – mit Timeout, damit
  /// getToken() (kann ohne Google-Dienste hängen) nie blockiert.
  Future<void> _syncFcmToken() async {
    // F-Droid-Build: kein Firebase, Push via UnifiedPush (falls aktiv).
    if (AppConstants.fdroidBuild) return;
    try {
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (token == null) return;
      await SupabaseDatabaseService(SupabaseService.client)
          .updateOwnProfile({'fcm_token': token});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthNotifier] FCM-Token-Sync fehlgeschlagen: $e');
      }
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    required DateTime birthDate,
    String? captchaToken,
  }) async {
    if (kDebugMode) {
      // PII (E-Mail, Name) nur im Debug-Modus loggen (Audit H4).
      debugPrint('[AuthNotifier] register() aufgerufen: name=$name, '
          'email=$email, gender=$gender');
    }
    state = const AsyncValue.loading();
    try {
      // Audit N-2: Der frühere GPS-Fix bei der Registrierung wurde entfernt
      // - die Werte wurden nie übertragen (tote Permission-Nutzung). Die
      // Fake-Account-Erkennung läuft serverseitig über den
      // process-location-check Flow bei Profil-Erstellung.

      final profile = await _auth.register(
        name: name,
        email: email,
        password: password,
        gender: gender,
        birthDate: birthDate,
        captchaToken: captchaToken,
      );
      if (kDebugMode) {
        debugPrint('[AuthNotifier] register() erfolgreich.');
      }
      // E-Mail für den Bestätigungs-Screen sichern. Bei aktivierter
      // E-Mail-Bestätigung liefert signUp KEINE Session (currentUser == null),
      // daher muss die Adresse aus dem Registrierungs-Formular kommen -
      // sonst schlägt "Bestätigungs-Mail erneut senden" fehl.
      _ref.read(pendingVerificationEmailProvider.notifier).state = email;
      // E-Mail + Passwort NUR IM SPEICHER für den stillen Auto-Login nach
      // der Bestätigung sichern (nie persistiert). Damit erkennt die App
      // die Bestätigung ohne Session und meldet den Nutzer automatisch an.
      _ref.read(pendingVerificationCredentialsProvider.notifier).state =
          (email: email, password: password, createdAt: DateTime.now());
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
    String? captchaToken,
  }) async {
    if (kDebugMode) {
      debugPrint('[AuthNotifier] login() aufgerufen: email=$email');
    }
    state = const AsyncValue.loading();
    try {
      await _auth.login(
        email: email,
        password: password,
        captchaToken: captchaToken,
      );
      debugPrint('[AuthNotifier] login erfolgreich');
      // Nach erfolgreichem Login sind die zwischengespeicherten
      // Registrierungs-Daten nicht mehr nötig.
      _ref.read(pendingVerificationEmailProvider.notifier).state = null;
      _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
      state = const AsyncValue.data(true);
      unawaited(_syncFromServer());
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AuthNotifier] login() FEHLER: $e');
      }
      state = AsyncValue.error(e, st);
      rethrow; // Fehler an den Aufrufer durchreichen
    }
  }

  Future<void> logout() async {
    await _auth.logout();
    _ref.read(pendingVerificationEmailProvider.notifier).state = null;
    _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
    _ref.read(passwordRecoveryPendingProvider.notifier).state = false;
    _ref.read(serverSyncDoneProvider.notifier).state = false;
    // MFA-Status zurücksetzen (keine Session -> keine Challenge/Setup).
    _ref.read(mfaStatusProvider.notifier).state = const MfaStatus.initial();
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
    String? captchaToken,
  }) async {
    await _auth.login(
      email: email,
      password: password,
      captchaToken: captchaToken,
    );
    _ref.read(pendingVerificationEmailProvider.notifier).state = null;
    _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
    state = const AsyncValue.data(true);
  }

  /// Löscht den Account serverseitig UND lokal vollständig.
  ///
  /// Audit M-12: Ein Server-Fehler wird NICHT mehr verschluckt - der
  /// lokale Reset erfolgt nur nach ERFOLGREICHER Löschung, damit der
  /// Nutzer nie glaubt, gelöscht zu sein, während die Daten weiter
  /// existieren. Der Fehler wird an den Aufrufer (UI) durchgereicht.
  ///
  /// Audit H-8: Nach erfolgreicher Löschung werden zusätzlich ALLE lokalen
  /// Reste entfernt: Signal-Keys/Sessions/Peer-Trust ([EncryptionService.
  /// clearAllData]), GPS-Verifizierungsstandort ([SecureLocationStorage]),
  /// Verifikations-Videos + Dateien ([VerificationService]),
  /// entschlüsselte Voice-Note-Temp-Dateien und das FCM-Geräte-Token
  /// (Audit N-20).
  Future<void> deleteAccount() async {
    // 1) Serverseitige Löschung FIRST - schlägt sie fehl, bleibt alles
    //    wie es ist und der Nutzer sieht den Fehler.
    await _auth.deleteAccount();

    // 2) Lokale Daten vollständig löschen (DSGVO Art. 17).
    try {
      if (!AppConstants.fdroidBuild) {
        await FirebaseMessaging.instance.deleteToken();
      }
    } catch (_) {
      // Best-effort: Token kann bereits ungültig sein.
    }
    try {
      await _ref.read(encryptionServiceProvider).clearAllData();
    } catch (e) {
      debugPrint('[AuthNotifier] Encryption-Cleanup fehlgeschlagen: $e');
    }
    try {
      await SecureLocationStorage.instance.clear();
    } catch (e) {
      debugPrint('[AuthNotifier] Standort-Cleanup fehlgeschlagen: $e');
    }
    try {
      await _ref.read(verificationServiceProvider).deleteAllLocalData();
    } catch (e) {
      debugPrint('[AuthNotifier] Video-Cleanup fehlgeschlagen: $e');
    }
    unawaited(cleanupDecryptedTempFiles());

    _ref.read(pendingVerificationEmailProvider.notifier).state = null;
    _ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
    _ref.read(mfaStatusProvider.notifier).state = const MfaStatus.initial();
    await _ref.read(settingsProvider.notifier).resetToDefaults();
    await _ref.read(userPreferencesProvider.notifier).resetToDefaults();
    await _ref.read(profileProvider.notifier).resetToDefaults();
    state = const AsyncValue.data(false);
  }
}

/// Prüft, ob der Demo-Modus (lokaler Mock) aktiv ist.
///
/// Entscheidung delegiert an die reine, testbare Funktion
/// [resolveDemoMode] (lib/utils/demo_mode.dart). Ohne Legacy-ApiConfig
/// gibt es keine Backend-URL mehr -> leerer String aktiviert die
/// URL-Heuristik nicht; ohne Supabase und ohne Flag bleibt der Modus
/// aus (fail-closed).
bool _isDemoMode() => resolveDemoMode(
      isReleaseMode: kReleaseMode,
      isSupabaseInitialized: SupabaseService.isInitialized,
      demoModeFlag: AppConstants.demoMode,
      baseUrl: '',
    );

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
    // Legacy-Aufräum: alte (ungesalzene) Credential-Hashes aus
    // SharedPreferences entfernen (Audit H6/M10).
    unawaited(
      prefs?.remove(AppConstants.prefsCredentialsKey) ?? Future.value(),
    );
    // Demo-Credentials (gesalzener Hash) liegen im Keystore/Keychain,
    // NICHT in SharedPreferences (Audit M10/H6).
    final secureStore = ref.watch(secureTokenStoreProvider);
    auth = AuthService(
      () async => prefs?.getString(AppConstants.prefsAuthKey),
      (String v) async => await prefs?.setString(AppConstants.prefsAuthKey, v),
      secureStore.readDemoCredentials,
      secureStore.writeDemoCredentials,
    );
  } else {
    // Weder Supabase noch Demo-Modus: Es gibt bewusst KEIN Legacy-Backend
    // mehr (der fruehere ApiClient mit Platzhalter-URL ist entfernt).
    // Fail-closed mit klarer Meldung statt garantiert fehlschlagender
    // Netzwerk-Calls.
    throw StateError(
      'Kein Auth-Backend verf\u00fcgbar: Supabase nicht initialisiert '
      'und Demo-Modus deaktiviert. Pr\u00fcfe .env / DEMO_MODE Build-Flag.',
    );
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
/// Wert ebenfalls (Speicher-only). ABLAUF (Audit M1): [createdAt] begrenzt
/// die Lebensdauer auf 15 Minuten – danach verweigert der Auto-Login das
/// Passwort weiterzureichen (das Passwort bleibt nie unbegrenzt im Speicher).
final pendingVerificationCredentialsProvider = StateProvider<
        ({String email, String password, DateTime createdAt})?>((ref) => null);

/// Zeigt an, ob ein Passwort-Reset (Recovery-Deep-Link) aussteht. Solange
/// true ist, erzwingt der Router den Reset-Screen; nach erfolgreichem
/// `updateUser` wird der Wert geleert.
final passwordRecoveryPendingProvider = StateProvider<bool>((ref) => false);

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



