import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/services/supabase_service.dart';

/// Kapselt die Supabase-MFA-API (TOTP/Authenticator-App) und stellt den
/// App-weiten MFA-Status für den Router bereit.
///
/// Unterstützt BEWUSST nur TOTP (Authenticator-Apps wie Google
/// Authenticator, Aegis, 2FAS, Apple Passcodes) – keine SMS (Betreiber-
/// Entscheidung). Passkeys (WebAuthn) sind separat über
/// [PasskeyAuth] integriert (Plattform-Plugin + Domain-Verknüpfung
/// assetlinks.json/AASA).
class MfaService {
  final SupabaseClient _client;

  MfaService(this._client);

  /// True, wenn eine Session existiert.
  bool get _hasSession => _client.auth.currentSession != null;

  /// Lädt den MFA-Zustand: aktuelles Sicherheitslevel (AAL) und ob
  /// verifizierte Faktoren existieren.
  Future<MfaStatus> loadStatus() async {
    if (!_hasSession) return const MfaStatus.initial();

    try {
      final aalResponse =
          _client.auth.mfa.getAuthenticatorAssuranceLevel();
      final factorsResponse = await _client.auth.mfa.listFactors();
      final hasVerifiedFactors = factorsResponse.all
          .any((f) => f.status == FactorStatus.verified);
      final hasAnyFactor = factorsResponse.all.isNotEmpty;

      return MfaStatus(
        currentAal: aalResponse.currentLevel?.name ?? 'aal1',
        hasVerifiedFactors: hasVerifiedFactors,
        hasAnyFactor: hasAnyFactor,
        loaded: true,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MfaService] loadStatus fehlgeschlagen: $e');
      }
      // Fail-closed: Bei Fehler keine Aussage – Router zeigt keinen
      // Setup-Prompt an, verlangt aber auch keine Challenge.
      return const MfaStatus.initial();
    }
  }

  /// Startet die TOTP-Einrichtung und liefert QR-URI + Secret.
  Future<({String factorId, String qrUri, String secret})> startTotpEnroll({
    String friendlyName = 'Wisp',
  }) async {
    final response = await _client.auth.mfa.enroll(
      issuer: 'Wisp',
      friendlyName: friendlyName,
      factorType: FactorType.totp,
    );
    final totp = response.totp;
    if (totp == null) {
      throw StateError('TOTP-Enrollment fehlgeschlagen (keine Daten).');
    }
    return (
      factorId: response.id,
      qrUri: totp.qrCode,
      secret: totp.secret,
    );
  }

  /// Verifiziert die TOTP-Einrichtung mit dem ersten Code aus der
  /// Authenticator-App (Challenge + Verify in einem Schritt).
  Future<void> verifyTotpEnroll({
    required String factorId,
    required String code,
  }) async {
    await _client.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code,
    );
  }

  /// Verwirft eine unvollständige TOTP-Einrichtung (z. B. Screen verlassen).
  Future<void> cancelEnroll(String factorId) async {
    try {
      await _client.auth.mfa.unenroll(factorId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MfaService] cancelEnroll fehlgeschlagen: $e');
      }
    }
  }

  /// Prüft einen TOTP-Code beim Login (Session damit auf AAL2 anheben).
  Future<void> verifyChallenge({required String code}) async {
    final factors = await _client.auth.mfa.listFactors();
    final totpFactor = factors.totp
        .firstWhere((f) => f.status == FactorStatus.verified);
    await _client.auth.mfa.challengeAndVerify(
      factorId: totpFactor.id,
      code: code,
    );
  }
}

/// MFA-Zustand für Routing-Entscheidungen.
class MfaStatus {
  const MfaStatus({
    this.currentAal = 'aal1',
    this.hasVerifiedFactors = false,
    this.hasAnyFactor = false,
    this.loaded = false,
  });

  /// Neutraler Initialzustand (nichts geladen, keine Aussage).
  const MfaStatus.initial()
      : currentAal = 'aal1',
        hasVerifiedFactors = false,
        hasAnyFactor = false,
        loaded = false;

  /// Aktuelles Assurance-Level der Session ('aal1' = nur Passwort,
  /// 'aal2' = zweiter Faktor verifiziert).
  final String currentAal;

  /// Verifizierte Faktoren vorhanden? (Challenge beim Login erzwingen)
  final bool hasVerifiedFactors;

  /// Irgendwelche Faktoren vorhanden? (auch unvollständige)
  final bool hasAnyFactor;

  /// Status erfolgreich geladen?
  final bool loaded;

  /// Beim Login nötig: Faktoren existieren, Session ist aber nur AAL1.
  bool get needsChallenge => loaded && hasVerifiedFactors && currentAal != 'aal2';

  /// Einrichtungshinweis sinnvoll: keine Faktoren, Session läuft.
  bool get shouldPromptSetup => loaded && !hasAnyFactor;
}

/// Provider für den [MfaService].
final mfaServiceProvider = Provider<MfaService>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('MfaService erfordert initialisiertes Supabase.');
  }
  return MfaService(SupabaseService.client);
});

/// App-weiter MFA-Status (wird von AuthNotifier nach Login/Sync geladen
/// und von den MFA-Screens nach Einrichtung/Verifikation aktualisiert).
final mfaStatusProvider = StateProvider<MfaStatus>((ref) {
  return const MfaStatus.initial();
});
