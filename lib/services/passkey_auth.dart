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
///  - Flutter 3.35+ / Dart 3.9+ und supabase_flutter mit Passkey-Support
///    (`signInWithPasskey` / `registerPasskey`).
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
    await SupabaseService.client.auth.signInWithPasskey(_authenticator);
  }

  /// Registriert ein neues Passkey für den bereits eingeloggten Nutzer.
  static Future<void> register() async {
    if (!SupabaseService.isInitialized) {
      throw AppException('Passkey-Setup ist derzeit nicht verfügbar.');
    }
    await SupabaseService.client.auth.registerPasskey(_authenticator);
  }
}
