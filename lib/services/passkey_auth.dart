import 'package:flutter/foundation.dart';
import 'package:passkeys/authenticator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/supabase_service.dart';

/// Kapselt die native Passkey-Anmeldung/-Registrierung.
///
/// Nutzt das `passkeys`-Plugin für die Plattform-Prompts (FaceID/TouchID/
/// Biometrie) und Supabase Auth für die WebAuthn-Ceremony (Server-Seite).
///
/// Voraussetzungen (sonst schlägt der Dialog/Login fehl):
///  - Supabase Dashboard: Passkeys aktiv, RP-ID = `auth.wispdating.de`
///  - Android: `assetlinks.json` + `<meta-data asset_statements>` (Manifest)
///  - iOS: Associated-Domains-Entitlement (`webcredentials:auth.wispdating.de`)
///  - Gerät: Sperrbildschirm (PIN/Muster/Biometrie) + aktuelle Google Play
///    Services (Credential Manager).
class PasskeyAuth {
  PasskeyAuth._();

  static final PasskeyAuthenticator _authenticator = PasskeyAuthenticator();

  /// Meldet den Nutzer mit einem vorhandenen Passkey an.
  ///
  /// Wirft bei Abbruch (Nutzer) oder Fehler (kein Passkey, Domain-Link
  /// fehlt). Der Aufrufer zeigt eine passende Meldung an.
  static Future<void> signIn() async {
    if (!SupabaseService.isInitialized) {
      throw AppException('Passkey-Login ist derzeit nicht verfügbar.');
    }
    try {
      await SupabaseService.client.auth.signInWithPasskey(_authenticator);
    } catch (e) {
      throw _explain(e, login: true);
    }
  }

  /// Registriert ein neues Passkey für den bereits eingeloggten Nutzer.
  static Future<void> register() async {
    if (!SupabaseService.isInitialized) {
      throw AppException('Passkey-Setup ist derzeit nicht verfügbar.');
    }
    try {
      await SupabaseService.client.auth.registerPasskey(_authenticator);
    } catch (e) {
      throw _explain(e, login: false);
    }
  }

  /// Test-Hook: Fehler-Mapping isoliert pruefbar machen.
  @visibleForTesting
  static AppException explainError(Object e, {required bool login}) =>
      _explain(e, login: login);

  /// Übersetzt kryptische Plugin-/WebAuthn-Fehler in verständliche Meldungen.
  ///
  /// Das Plugin meldet DOM-Fehlertypen als Code wie
  /// `android-unhandled: NotAllowedError`. Die häufigsten Ursachen:
  ///  - NotAllowedError: Abbruch/Timeout oder kein Sperrbildschirm aktiv
  ///  - SecurityError: RP-ID/Domain-Verknüpfung (assetlinks.json) passt nicht
  ///  - InvalidStateError: Auf diesem Gerät existiert bereits ein Passkey
  static AppException _explain(Object e, {required bool login}) {
    final action = login ? 'Anmeldung' : 'Einrichtung';
    // Plugin-Fehler kommen teils als PlatformException, teils als generisches
    // FlutterError - daher String-basiert auf den Fehlertyp prüfen.
    final text = e.toString();

    if (text.contains('cancelled') ||
        text.toLowerCase().contains('cancellationexception')) {
      return AppException('Passkey-$action abgebrochen.');
    }
    if (text.contains('NotAllowedError')) {
      return AppException(
        'Passkey-$action wurde abgebrochen oder ist abgelaufen. '
        'Vergewissere dich, dass dein Gerät einen Sperrbildschirm '
        '(PIN, Muster oder Biometrie) hat, und versuche es erneut.',
      );
    }
    if (text.contains('InvalidStateError')) {
      return AppException(
        'Auf diesem Gerät existiert bereits ein Passkey für dieses Konto.',
      );
    }
    if (text.contains('SecurityError')) {
      return AppException(
        'Die App konnte ihre Domain-Zugehörigkeit nicht nachweisen '
        '(Passkey-Domain-Verknüpfung). Prüfe, ob die neueste App-Version '
        'installiert ist, und melde es dem Support, falls es bleibt.',
      );
    }
    if (text.contains('android-sync-account-not-available')) {
      return AppException(
        'Der Passkey konnte nicht verschlüsselt gespeichert werden. '
        'Stelle sicher, dass du auf dem Gerät mit einem Google-Konto '
        'angemeldet bist und die Google Play Services aktuell sind.',
      );
    }
    if (text.contains('android-timeout')) {
      return AppException(
        'Zeitüberschreitung beim Passkey-$action. Bitte versuche es '
        'gleichzeitig am Bildschirm erneut.',
      );
    }
    if (text.contains('no_credential') || text.contains('NoCredential')) {
      return AppException(
        login
            ? 'Kein Passkey für dieses Konto gefunden. Richte zuerst einen '
                'unter Einstellungen ein.'
            : 'Kein Passkey-Speicher verfügbar. Prüfe Sperrbildschirm und '
                'Google Play Services.',
      );
    }

    // Server lehnt die Anfrage ab, BEVOR der native Dialog erscheint
    // ("schlägt direkt fehl"): GoTrue liefert die WebAuthn-Challenge.
    // Typische Ursachen: Passkeys/WebAuthn im Supabase-Dashboard nicht
    // aktiviert oder RP-ID/Origins falsch konfiguriert.
    final isAuthApiError = text.contains('AuthApiException') ||
        RegExp(r'\bstatus: 4\d\d\b').hasMatch(text) ||
        text.toLowerCase().contains('webauthn');
    if (isAuthApiError) {
      debugPrint('[PasskeyAuth] Server-Fehler: $e');
      return AppException(
        'Der Server hat die Passkey-Anfrage abgelehnt. Bitte prüfe in den '
        'Supabase-Einstellungen, ob "Passkeys" aktiviert ist und die '
        'RP-ID auf auth.wispdating.de gesetzt ist.',
      );
    }

    // Unbekannter Fehler: Details NIE durchreichen (auch nicht im Debug -
    // Profile-Builds haben kReleaseMode == false und wuerden sonst leaken).
    // Die vollstaendige Meldung landet nur im Log.
    debugPrint('[PasskeyAuth] $action fehlgeschlagen: $e');
    return AppException(
      'Passkey-$action fehlgeschlagen. Bitte versuche es später erneut.',
    );
  }
}
