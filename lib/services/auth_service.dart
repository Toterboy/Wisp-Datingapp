import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:wisp/services/app_auth_service.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/utils/constants.dart';

/// Mock-Authentifizierung (kein echtes Backend, keine echten Berechtigungen).
///
/// NUR Demo-Modus (resolveDemoMode). Sicherheits-Regeln seit Audit H7/M10:
/// - Ohne registrierte Zugangsdaten schlägt der Login FEHL (fail-closed).
///   Früher wurde hier jede E-Mail/Passwort-Kombi akzeptiert (Auth-Bypass).
/// - Zugangsdaten werden als GESALZENER SHA-256-Hash gespeichert (Format
///   `salt$hash`) und liegen im Keystore/Keychain (siehe AuthProvider-
///   Wiring), nicht mehr in SharedPreferences.
class AuthService implements AppAuthService {
  AuthService(
    this._getStoredUserId,
    this._storeUserId,
    this._getStoredCredentials,
    this._storeCredentials,
  );

  /// Callback, um die gespeicherte User-ID zu lesen.
  final Future<String?> Function() _getStoredUserId;

  /// Callback, um die User-ID zu speichern.
  final Future<void> Function(String) _storeUserId;

  /// Callback, um die gespeicherten Zugangsdaten (`salt$hash`) zu lesen.
  final Future<String?> Function() _getStoredCredentials;

  /// Callback, um die Zugangsdaten (`salt$hash`) zu speichern.
  final Future<void> Function(String) _storeCredentials;

  /// Aktuell eingeloggter Nutzer (null = ausgeloggt).
  String? _currentUserId;

  /// True, wenn ein Nutzer eingeloggt ist.
  bool get isLoggedIn => _currentUserId != null && _currentUserId!.isNotEmpty;

  /// Lädt den Login-Status aus dem lokalen Speicher.
  @override
  Future<bool> restoreSession() async {
    _currentUserId = await _getStoredUserId();
    return isLoggedIn;
  }

  /// Registriert einen neuen Nutzer (Mock) und loggt ihn ein.
  ///
  /// Speichert nur einen GESALZENEN SHA-256-Hash der Zugangsdaten
  /// (E-Mail + Passwort + Zufalls-Salt), niemals das Passwort im Klartext.
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
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _currentUserId = AppConstants.currentUserId;
    await _storeUserId(_currentUserId!);
    await _storeCredentials(hashCredentialsForTest(email, password));
    return UserProfile(
      id: _currentUserId!,
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

  /// Loggt einen bestehenden Nutzer ein (Mock).
  ///
  /// Prüft E-Mail + Passwort gegen den gespeicherten, gesalzenen Hash.
  /// Wirft bei falschen Daten – und auch dann, wenn noch KEIN Demo-Konto
  /// registriert wurde (kein Auth-Bypass mehr, Audit H7).
  @override
  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final stored = await _getStoredCredentials();
    if (stored == null || stored.isEmpty) {
      throw AppException(
        'Kein Demo-Konto vorhanden. Bitte registriere dich zuerst.',
      );
    }
    if (!_verify(stored, email, password)) {
      throw AppException('Email oder Passwort ist falsch.');
    }
    _currentUserId = AppConstants.currentUserId;
    await _storeUserId(_currentUserId!);
  }

  /// Hasht E-Mail + Passwort mit SHA-256 und Zufalls-Salt — NUR für den
  /// lokalen Demo-Modus.
  ///
  /// Format: `<saltHex>$<sha256(salt + email + \x00 + password)>`.
  /// ⚠️ Kein KDF (PBKDF2/Argon2) – für den Mock ausreichend, da die Daten
  /// ausschließlich im Keystore liegen und niemals echte User-Daten berührt
  /// werden. In Produktion hasht Supabase Auth (GoTrue) serverseitig.
  @visibleForTesting
  static String hashCredentialsForTest(String email, String password) {
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    return '${_hex(salt)}\$${_hash(salt, email, password)}';
  }

  /// Prüft Zugangsdaten gegen einen gespeicherten `salt$hash`-String
  /// (für Tests öffentlich zugänglich).
  @visibleForTesting
  static bool verifyCredentialsForTest(
    String stored,
    String email,
    String password,
  ) {
    return _verify(stored, email, password);
  }

  static final Random _random = Random.secure();

  static String _hash(List<int> salt, String email, String password) {
    final digest = sha256.convert(
      salt + utf8.encode('$email\x00$password'),
    );
    return digest.toString();
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static bool _verify(String stored, String email, String password) {
    final parts = stored.split(r'$');
    if (parts.length != 2) return false;
    final salt = <int>[];
    final hexSalt = parts[0];
    if (hexSalt.length != 32 || hexSalt.length.isOdd) return false;
    for (var i = 0; i < hexSalt.length; i += 2) {
      final byte = int.tryParse(hexSalt.substring(i, i + 2), radix: 16);
      if (byte == null) return false;
      salt.add(byte);
    }
    return _hash(salt, email, password) == parts[1];
  }

  /// Logout - entfernt die Session lokal.
  @override
  Future<void> logout() async {
    _currentUserId = null;
    // Leeren String speichern, damit bei restoreSession kein "eingeloggt"
    // angenommen wird. Eine leere ID wird wie "ausgeloggt" behandelt.
    await _storeUserId('');
  }

  /// Löscht den Account lokal (Mock).
  @override
  Future<void> deleteAccount() async {
    _currentUserId = null;
    await _storeUserId('');
    await _storeCredentials('');
  }
}

