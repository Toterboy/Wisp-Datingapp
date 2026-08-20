import 'package:flutter/foundation.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/services/api_client.dart';
import 'package:wisp/services/app_auth_service.dart';
import 'package:wisp/services/encryption_service.dart';
import 'package:wisp/services/secure_storage.dart';

/// Echte Authentifizierung gegen den Signaling-Server (ersetzt den Mock
/// [AuthService]). Nutzt [ApiClient] (HTTPS + Zertifikat-Pinning),
/// speichert Tokens sicher in [SecureTokenStore] und veröffentlicht nach
/// Login/Registrierung das eigene Signal-PreKey-Bundle, damit andere Nutzer
/// Ende-zu-Ende-Sessions zu uns aufbauen können.
class ApiAuthService implements AppAuthService {
  ApiAuthService(this._api, this._tokens, this._encryption);

  final ApiClient _api;
  final SecureTokenStore _tokens;
  final EncryptionService _encryption;

  /// true, wenn ein gültiges Access-Token existiert UND noch nicht
  /// abgelaufen ist. Prüft im Gegensatz zur vorherigen Version NICHT
  /// nur die Existenz einer User-ID, sondern validiert das Token aktiv.
  @override
  Future<bool> restoreSession() async {
    final uid = await _tokens.userId;
    if (uid == null || uid.isEmpty) return false;

    // Token nur dann als gültig betrachten, wenn es sich aktiv
    // verwenden lässt (refresh-Versuch als Liveness-Check).
    final rt = await _tokens.refreshToken;
    if (rt == null || rt.isEmpty) return false;

    try {
      await _api.refresh(refreshToken: rt);
      return true;
    } catch (_) {
      // Token abgelaufen oder invalidiert → Nutzer muss sich neu anmelden.
      await _tokens.clear();
      return false;
    }
  }

  /// [captchaToken] wird ignoriert – der Signaling-Server hat kein
  /// CAPTCHA-Endpoint (nur Supabase Auth unterstützt es aktuell).
  @override
  Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    required DateTime birthDate,
    String? inviteCode,
    double? latitude,
    double? longitude,
    String? captchaToken,
  }) async {
    // Schlüssel müssen bereit sein, bevor wir das Bundle hochladen.
    await _encryption.initialized;

    final birth = '${birthDate.year.toString().padLeft(4, '0')}-'
        '${birthDate.month.toString().padLeft(2, '0')}-'
        '${birthDate.day.toString().padLeft(2, '0')}';

    if (kDebugMode) {
      // PII (E-Mail, Geburtsdatum) nur im Debug-Modus loggen (Audit H4).
      debugPrint('[ApiAuthService] registriere: email=$email, gender=$gender, birthDate=$birth');
    }
    final profilePayload = {
      'name': name,
      'gender': gender ?? 'unknown',
      'genderPreference': 'all',
      'birthDate': birth,
      'bio': '',
      'interests': <String>[],
      'latitude': latitude,
      'longitude': longitude,
      'personalityType': 'INTJ',
      'maxDistanceKm': 100,
      'ageRangeMin': 18,
      'ageRangeMax': 99,
    };
    if (kDebugMode) {
      // Enthält lat/lng – nur im Debug-Modus loggen (Audit H4).
      debugPrint('[ApiAuthService] Profile payload: $profilePayload');
    }
    final auth = await _api.register(
      email: email,
      password: password,
      profile: profilePayload,
    );
    // Sicherheit: Kein Token-Präfix in Logs - nicht einmal gekürzt.
    debugPrint('[ApiAuthService] Registration response: userId=${auth.userId}');
    await _tokens.saveTokens(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
      userId: auth.userId!,
    );
    await _publishOwnPreKeys(auth.accessToken);

    return UserProfile(
      id: auth.userId!,
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

  /// [captchaToken] wird ignoriert – der Signaling-Server hat kein
  /// CAPTCHA-Endpoint (nur Supabase Auth unterstützt es aktuell).
  @override
  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    final auth = await _api.login(email: email, password: password);
    await _tokens.saveTokens(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
      userId: auth.userId!,
    );
    await _publishOwnPreKeys(auth.accessToken);
  }

  /// Lädt das eigene PreKey-Bundle hoch, sofern die Schlüssel bereit sind.
  Future<void> _publishOwnPreKeys(String token) async {
    try {
      await _encryption.initialized;
      final bundle = await _encryption.exportPreKeyBundle();
      await _api.uploadPreKeys(token, bundle);
    } catch (e) {
      // Nicht fatal: E2E funktioniert erst, sobald das Bundle vorhanden ist.
      // Ein erneuter Upload kann später (z. B. beim nächsten Login) erfolgen.
    }
  }

  @override
  Future<void> logout() async {
    final at = await _tokens.accessToken;
    final rt = await _tokens.refreshToken;
    if (at != null && rt != null) {
      try {
        await _api.logout(accessToken: at, refreshToken: rt);
      } catch (_) {
        // Best-effort - lokales Löschen erfolgt trotzdem.
      }
    }
    await _tokens.clear();
  }

  @override
  Future<void> deleteAccount() async {
    final at = await _tokens.accessToken;
    final rt = await _tokens.refreshToken;
    if (at != null && rt != null) {
      try {
        await _api.deleteAccount(accessToken: at, refreshToken: rt);
      } catch (_) {
        // Best-effort - lokales Löschen erfolgt trotzdem.
      }
    }
    await _tokens.clear();
  }
}

