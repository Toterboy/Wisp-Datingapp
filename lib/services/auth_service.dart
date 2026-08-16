import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:wisp/services/app_auth_service.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/utils/constants.dart';

/// Mock-Authentifizierung (kein echtes Backend, keine echten Berechtigungen).
///
/// Simuliert Login/Registrierung mit einer kleinen Verzögerung, damit die
/// UI Ladezustände realistisch darstellen kann. Registrierte Zugangsdaten
/// (E-Mail + Passwort) werden lokal gehalten, damit sich ein registrierter
/// Nutzer später mit exakt denselben Daten einloggen kann.
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

  /// Callback, um die gespeicherten Zugangsdaten (E-Mail:Passwort) zu lesen.
  final Future<String?> Function() _getStoredCredentials;

  /// Callback, um die Zugangsdaten (E-Mail:Passwort) zu speichern.
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
  /// Speichert nur einen SHA-256-Hash der Zugangsdaten (E-Mail + Passwort),
  /// NIEMALS das Passwort im Klartext. So kann auch bei lokalem Speicher
  /// kein Klartext-Passwort ausgelesen werden.
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
  /// Prüft E-Mail + Passwort gegen den gespeicherten Hash.
  /// Wirft bei falschen Daten eine [AppException].
  @override
  Future<void> login({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final stored = await _getStoredCredentials();
    if (stored == null || stored.isEmpty) {
      // Keine registrierten Daten (z. B. anderer Demo-Stand): trotzdem
      // einloggen, damit bestehender Flow nicht blockiert.
      _currentUserId = AppConstants.currentUserId;
      await _storeUserId(_currentUserId!);
      return;
    }
    if (stored != hashCredentialsForTest(email, password)) {
      throw AppException('Email oder Passwort ist falsch.');
    }
    _currentUserId = AppConstants.currentUserId;
    await _storeUserId(_currentUserId!);
  }

  /// Hasht E-Mail + Passwort mit SHA-256 — NUR für den lokalen Demo-Modus.
  ///
  /// ⚠️ KEIN Salt, KEIN KDF (Argon2/PBKDF2). Diese Funktion ist AUSSCHLIESSLICH
  /// für den Mock-[AuthService] im Demo-Modus gedacht. Sie kommt NIEMALS mit
  /// echten User-Daten in Berührung.
  ///
  /// In Produktion übernimmt Supabase Auth das Passwort-Hashing serverseitig
  /// (Argon2/bcrypt via GoTrue). Der Klartext verlässt das Gerät ausschließlich
  /// über TLS geschützte HTTPS-Verbindungen und wird lokal nicht persistiert.
  @visibleForTesting
  static String hashCredentialsForTest(String email, String password) {
    final digest = sha256.convert(utf8.encode('$email\x00$password'));
    return digest.toString();
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

