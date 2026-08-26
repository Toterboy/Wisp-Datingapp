import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/services/app_auth_service.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/encryption_service.dart';
import 'package:wisp/services/secure_storage.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Echte Authentifizierung über Supabase Auth (ersetzt den Mock [AuthService]).
///
/// Speichert Tokens zusätzlich im [SecureTokenStore] (Kompatibilität zum
/// bestehenden System), primär nutzt Supabase Auth aber seine eigene
/// persistente Session.
class SupabaseAuthService implements AppAuthService {
  SupabaseAuthService(this._supabase, this._tokens, this._encryption, this._database);

  final SupabaseClient _supabase;
  final SecureTokenStore _tokens;
  final EncryptionService _encryption;
  final SupabaseDatabaseService _database;

  /// True, wenn eine gültige Supabase-Session existiert und die E-Mail
  /// des Nutzers bestätigt ist.
  ///
  /// STARTUP-PERFORMANCE: Der Check ist bewusst SYNCHRON (nur lokale
  /// Session-Daten) und blockiert den App-Start nicht durch einen
  /// Netzwerk-Roundtrip. Die serverseitige Validierung läuft im Hintergrund
  /// ([_validateSession]): Existiert der Nutzer nicht mehr (Datenbank-Reset,
  /// Dashboard-Löschung, Session aus anderem Projekt), wird die Session
  /// verworfen; der damit ausgelöste `signedOut`-Event setzt den
  /// Auth-Status über [AuthNotifier] auf "ausgeloggt" - der Router schickt
  /// den Nutzer dann auf Login statt in den E-Mail-Bestätigungs-Screen.
  /// Netzwerkfehler behalten die Session (offline-tolerant).
  @override
  Future<bool> restoreSession() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return false;
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    if (user.emailConfirmedAt == null) return false;

    // Serverseitige Validierung NICHT abwarten (Startzeit!).
    unawaited(_validateSession());
    // Safety-Numbers (Signal-Fingerprint) benötigen die eigene User-ID.
    _encryption.localUserId = user.id;
    return true;
  }

  /// Prüft die lokale Session im Hintergrund gegen die Auth-API.
  Future<void> _validateSession() async {
    try {
      final userResponse = await _supabase.auth
          .getUser()
          .timeout(const Duration(seconds: 5));
      final serverUser = userResponse.user;
      if (serverUser == null || serverUser.emailConfirmedAt == null) {
        // E-Mail (noch) nicht bestätigt bzw. User weg: Session verwerfen.
        await _clearLocalSession();
      }
    } on TimeoutException {
      // Langsames Netz – lokale Session nicht verwerfen.
    } on AuthRetryableFetchException {
      // Netzwerk-/Serverfehler – lokale Session nicht verwerfen.
    } on AuthException catch (e) {
      // Nutzer existiert serverseitig nicht mehr oder Session ist
      // invalidiert: lokale Session und Tokens verwerfen, damit der
      // Nutzer sauber auf Login/Registrierung landet.
      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] Session serverseitig ungültig: $e');
      }
      await _clearLocalSession();
    } catch (e) {
      // Unbekannter Fehler – Session behalten (offline-tolerant).
      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] getUser()-Validierung fehlgeschlagen: $e');
      }
    }
  }

  /// Verwirft die lokale Session samt gespeicherter Tokens.
  ///
  /// [GoTrueClient.signOut] ist ohne Angabe rein lokal (scope: local) –
  /// es wird kein Netzwerk-Call unternommen, der hängen bleiben könnte.
  Future<void> _clearLocalSession() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Best-effort
    }
    await _tokens.clear();
  }

  /// Prüft, ob der eingeloggte Nutzer seine E-Mail bestätigt hat.
  bool isEmailConfirmed() {
    final user = _supabase.auth.currentUser;
    return user != null && user.emailConfirmedAt != null;
  }

  /// Registriert einen neuen Nutzer in Supabase Auth + Datenbank und loggt ihn ein.
  ///
  /// [captchaToken]: CAPTCHA-Token (hCaptcha/Turnstile) für den Bot-Schutz.
  /// Supabase validiert es serverseitig, wenn im Dashboard CAPTCHA aktiviert
  /// ist; ohne Dashboard-Aktivierung wird das Token ignoriert.
  @override
  Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    required DateTime birthDate,
    double? latitude,
    double? longitude,
    String? captchaToken,
  }) async {
    await _encryption.initialized;

    // Audit H-5 (Betreiber-Entscheidung): Das Invite-Code-System wurde in
    // Migration 057 vollständig entfernt - Registrierung ist offen
    // (geschützt durch CAPTCHA im Dashboard + serverseitige Rate-Limits).

    // 0) Plattform-Sperre (Migration 045): Gesperrte E-Mail-Adressen
    //    dürfen sich nicht (neu) registrieren. Der serverseitige
    //    handle_new_user-Trigger erzwingt das zusätzlich (RAISE 'email_banned').
    //    Hier geht es um die UX: Der Nutzer bekommt sofort den
    //    Entsperrungs-Flow angeboten statt eines generischen Fehlers.
    final banStatus = await _database.checkEmailBanStatus(email);
    if (banStatus.banned) {
      throw EmailBannedException(email: email.trim(), reason: banStatus.reason);
    }

    final birth = '${birthDate.year.toString().padLeft(4, '0')}-'
        '${birthDate.month.toString().padLeft(2, '0')}-'
        '${birthDate.day.toString().padLeft(2, '0')}';

    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] registriere: gender=$gender');
    }

    // 1) Auth-User anlegen.
    // raw_user_meta_data enthält ALLE bei der Registrierung erfassten
    // Nutzerdaten – der serverseitige handle_new_user-Trigger liest diese
    // Felder aus und legt das Profil mit SECURITY DEFINER an. Dadurch ist
    // kein clientseitiger INSERT nötig.
    //
    // WICHTIG: Das Passwort darf NIEMALS in raw_user_meta_data landen!
    // Nur unkritische Profilfelder: name, gender, birth_date.
    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] signUp() wird aufgerufen: email=$email');
      debugPrint('[SupabaseAuthService] Supabase-URL: ${_supabase.rest.url}');
    }

    final User user;
    final AuthResponse authResponse;
    try {
      authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
        captchaToken: captchaToken,
        data: {
          'name': name,
          'gender': gender ?? 'unknown',
          'birth_date': birth,
        },
      );
      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] signUp() abgeschlossen.');
      }

      user = authResponse.user ?? (throw AppException('Registrierung fehlgeschlagen. Bitte versuche es erneut.'));
    } on AuthException catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] AuthException: ${e.message} (Code: ${e.statusCode})');
      }
      // Serverseitige Sperre (handle_new_user-Trigger, Migration 045):
      // auch dann den Entsperrungs-Flow anbieten, wenn der Vorab-Check
      // nicht griff (z. B. altes App-Build).
      if (e.message.toLowerCase().contains('email_banned')) {
        throw EmailBannedException(email: email.trim());
      }
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SupabaseAuthService] UNERWARTETER Fehler bei signUp(): $e');
        debugPrint('[SupabaseAuthService] StackTrace: $st');
      }
      rethrow;
    }

    // Safety-Numbers (Signal-Fingerprint) benötigen die eigene User-ID.
    _encryption.localUserId = user.id;

    // 4) Profil-Erstellung:
    //    Der serverseitige handle_new_user-Trigger (SECURITY DEFINER) hat
    //    das Profil bereits in public.profiles angelegt. Kein clientseitiger
    //    INSERT nötig – wir konstruieren das UserProfile aus den lokal
    //    vorhandenen Daten. Der Trigger garantiert, dass das Profil in der
    //    DB existiert, sobald der Nutzer nach E-Mail-Bestätigung vollständig
    //    authentifiziert ist.
    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] Registration erfolgreich: userId=${user.id}');
      debugPrint('[SupabaseAuthService] Profil wurde via handle_new_user-Trigger angelegt.');
      debugPrint('[SupabaseAuthService] Bestätigungs-E-Mail wurde versendet.');
    }

    // Token zusätzlich für Kompatibilität mit dem bestehenden SecureTokenStore sichern.
    final session = authResponse.session;
    if (session != null) {
      await _tokens.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken ?? '',
        userId: user.id,
      );
    }

    // UserProfile aus den lokalen Registrierungsdaten konstruieren.
    // Nach E-Mail-Bestätigung wird das vollständige Profil via
    // fetchOwnProfile() aus der DB gelesen – dann inklusive aller
    // serverseitig gesetzten Felder.
    return UserProfile(
      id: user.id,
      name: name,
      bio: '',
      interests: const [],
      photos: const [],
      city: '',
      gender: gender,
      genderPreference: 'all',
      birthDate: birthDate,
    );
  }

  /// Loggt einen Nutzer per E-Mail + Passwort in Supabase Auth ein.
  ///
  /// [captchaToken]: CAPTCHA-Token (hCaptcha/Turnstile) für den Bot-Schutz –
  /// Supabase validiert es serverseitig, wenn im Dashboard CAPTCHA
  /// aktiviert ist.
  @override
  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] login aufgerufen');
    }

    // Plattform-Sperre (Migration 045): Auch der Login mit einer
    // gesperrten E-Mail-Adresse wird blockiert - der Nutzer soll nur
    // den Entsperrungs-Flow sehen.
    final banStatus = await _database.checkEmailBanStatus(email);
    if (banStatus.banned) {
      throw EmailBannedException(email: email.trim(), reason: banStatus.reason);
    }

    final authResponse = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
      captchaToken: captchaToken,
    );

    final session = authResponse.session;
    if (session != null) {
      await _tokens.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken ?? '',
        userId: authResponse.user!.id,
      );
    }
    // Safety-Numbers (Signal-Fingerprint) benötigen die eigene User-ID.
    _encryption.localUserId = authResponse.user!.id;

    if (kDebugMode) {
      debugPrint('[SupabaseAuthService] login erfolgreich.');
    }
  }

  /// Schickt eine E-Mail zur Bestätigung der Adresse (z.B. nach Login bei unbestätigtem Account).
  Future<void> sendEmailConfirmation() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw AppException('Nicht eingeloggt.');
    await _supabase.auth.resend(
      type: OtpType.signup,
      email: user.email ?? '',
    );
  }

  /// Loggt den Nutzer aus Supabase Auth aus und löscht lokale Tokens.
  ///
  /// ASVS 7.4.1: `SignOutScope.global` ruft den GoTrue-Logout-Endpoint mit
  /// dem Access-Token auf und widerruft die Session serverseitig (Refresh-
  /// Token invalidiert). Erst danach lokaler SignOut + Token-Löschung.
  /// Netzwerkfehler blockieren den Logout nicht (best-effort).
  @override
  Future<void> logout() async {
    try {
      await _supabase.auth
          .signOut(scope: SignOutScope.global)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline-Fallback: nur lokal ausloggen; die serverseitige Session
      // läuft bis zum Ablauf des Refresh-Tokens weiter.
      try {
        await _supabase.auth.signOut();
      } catch (_) {
        // Best-effort: lokales Löschen der Tokens erfolgt trotzdem.
      }
    }
    await _tokens.clear();
  }

  /// Löscht den Nutzer vollständig über die serverseitige Edge Function
  /// 'delete-account' (DSGVO Art. 17). Der Auth-User selbst wird mit dem
  /// service_role-Key gelöscht; der Client besitzt diesen Key nie.
  ///
  /// Audit M-12: Ein FEHLSCHLAG der Löschung wird nicht mehr verschluckt -
  /// vorher glaubte der Nutzer, sein Account sei gelöscht, während alle
  /// Server-Daten erhalten blieben. Bei Fehler wirft diese Methode und
  /// der Aufrufer ([AuthNotifier]) unterlässt den lokalen Reset.
  @override
  Future<void> deleteAccount() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        final response = await _supabase.functions
            .invoke('delete-account')
            .timeout(const Duration(seconds: 20));
        final data = response.data;
        if (response.status != 200 ||
            (data is Map && data['deleted'] != true)) {
          throw AppException(
            'Die Löschung konnte auf dem Server nicht abgeschlossen '
            'werden. Bitte prüfe deine Verbindung und versuche es erneut.',
          );
        }
      } on AppException {
        rethrow;
      } catch (e) {
        throw AppException(
          'Die Löschung konnte nicht an den Server übermittelt werden. '
          'Dein Account wurde NICHT gelöscht - bitte versuche es erneut.',
        );
      }
    }
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Best-effort
    }
    await _tokens.clear();
  }
}
