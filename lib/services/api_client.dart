import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:wisp/utils/cert_pinning.dart';
import 'package:wisp/utils/peer_id.dart';

/// Zentrale Konfiguration der Backend-Endpunkte.
///
/// In Produktion über `-dart-define=API_BASE_URL=https://...` oder eine
/// Build-Konfiguration setzen. Niemals `http://` verwenden (TLS-Zwang!,
/// unten erzwungen).
class ApiConfig {
  ApiConfig._();

  /// Basis-URL des Signaling/API-Servers (muss HTTPS sein).
  static const String baseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'https://signaling.example.com');

  /// WebSocket-URL für Signaling, abgeleitet von [baseUrl] (immer wss://).
  static String get signalingWsUrl {
    final uri = Uri.parse(baseUrl);
    if (!uri.isScheme('https')) {
      // TLS-Zwang (Audit M9): http:// wird nicht stillschweigend akzeptiert.
      throw StateError('API_BASE_URL muss HTTPS sein: $baseUrl');
    }
    return uri.replace(scheme: 'wss', path: '/ws').toString();
  }
}

/// Schlanke API-Schicht zum Signaling-Server.
///
/// - Erzwingt TLS (HTTPS) und Zertifikat-Pinning (s. [CertPinning]).
/// - Hängt bei Bedarf das Access-Token (Bearer) an.
/// - Kapselt Login/Refresh/Profil/Matching/PreKeys/ICE.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? _buildPinnedClient();

  final http.Client _client;

  /// Baut einen HTTP-Client mit Zertifikat-Pinning (kein Plain-HTTP).
  static http.Client _buildPinnedClient() {
    if (kIsWeb) {
      // Web kann keine Custom-Cert-Pinning via dart:io; hier auf
      // Browser-Mechanismen (HPKP/CRT-Logs) sowie CSP vertrauen.
      return http.Client();
    }
    return IOClient(CertPinning.pinnedHttpClient());
  }

  Map<String, String> _headers({String? token}) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _postJson(
    String path, {
    required Map<String, dynamic> body,
    String? token,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    if (kDebugMode) {
      debugPrint('[ApiClient] POST $uri');
    }
    // Request-Body NICHT loggen (kann Passwörter, Tokens oder E-Mails enthalten).
    final res = await _client.post(
      uri,
      headers: _headers(token: token),
      body: jsonEncode(body),
    );
    if (kDebugMode) {
      debugPrint('[ApiClient] Response status: ${res.statusCode}');
    }
    return _handle(res);
  }

  Future<Map<String, dynamic>> _getJson(String path, {String? token}) async {
    final res = await _client.get(
      Uri.parse('${ApiConfig.baseUrl}$path'),
      headers: _headers(token: token),
    );
    return _handle(res);
  }

  Map<String, dynamic> _handle(http.Response res) {
    // Response-Body NICHT loggen (kann sensible Daten wie Tokens enthalten).
    if (kDebugMode) {
      debugPrint('[ApiClient] _handle status: ${res.statusCode}');
    }
    final body = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : <String, dynamic>{};
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    // 401 - Token abgelaufen; der Aufrufer sollte refresh() versuchen.
    throw ApiException(statusCode: res.statusCode, message: body['error']?.toString() ?? 'HTTP ${res.statusCode}');
  }

  // ─── Auth ──────────────────────────────────────────────────────────────
  Future<AuthResult> register({
    required String email,
    required String password,
    required Map<String, dynamic> profile,
  }) async {
    final r = await _postJson('/api/register', body: {'email': email, 'password': password, ...profile});
    return AuthResult.fromJson(r);
  }

  Future<AuthResult> login({required String email, required String password}) async {
    final r = await _postJson('/api/login', body: {'email': email, 'password': password});
    return AuthResult.fromJson(r);
  }

  /// Erneuert das Access-Token. Bei Scheitern (Rotation/Diebstahl) wird
  /// [ApiException] mit 401 geworfen - UI muss neu anmelden.
  Future<AuthResult> refresh({required String refreshToken}) async {
    final r = await _postJson('/api/refresh', body: {'refreshToken': refreshToken});
    return AuthResult.fromJson(r, hasUserId: false);
  }

  Future<void> logout({required String accessToken, required String refreshToken}) async {
    try {
      await _postJson('/api/logout', body: {'refreshToken': refreshToken}, token: accessToken);
    } on ApiException {
      // Best-effort: auch bei Fehler gilt Logout lokal.
    }
  }

  Future<void> deleteAccount({required String accessToken, required String refreshToken}) async {
    try {
      await _postJson('/api/account', body: {'refreshToken': refreshToken}, token: accessToken);
    } on ApiException {
      // Best-effort: auch bei Fehler gilt Löschung lokal.
    }
  }

  // ─── Profil / Matching 
  Future<Map<String, dynamic>> getProfile(String token) => _getJson('/api/me', token: token);
  Future<void> updateProfile(String token, Map<String, dynamic> profile) =>
      _postJson('/api/me', body: profile, token: token);

  Future<List<dynamic>> fetchMatches(String token) async {
    final r = await _getJson('/api/matches', token: token);
    return (r['matches'] as List?) ?? [];
  }

  /// Liefert die STUN/TURN-Konfiguration inkl. kurzlebiger TURN-Credentials.
  Future<IceConfig> fetchIceConfig(String token) async {
    final r = await _getJson('/api/ice', token: token);
    return IceConfig.fromJson(r);
  }

  // ─── PreKey-Verteiler (E2E-Setup) ────────────────────────────────────────────────────────────
  Future<void> uploadPreKeys(String token, Map<String, dynamic> bundle) =>
      _postJson('/api/prekeys', body: bundle, token: token);

  /// Holt das öffentliche PreKey-Bundle eines Kommunikationspartners - die
  /// Basis für den Aufbau einer Signal-Protocol-Session (s. prekey_service).
  ///
  /// [peerId] muss eine valide UUID sein (Audit M1) und wird zusätzlich
  /// URL-encoded, bevor er in den Pfad eingebaut wird.
  Future<Map<String, dynamic>> fetchPeerPreKeys(String token, String peerId) async {
    if (!isValidPeerId(peerId)) {
      throw ApiException(statusCode: 400, message: 'Ungültige Peer-ID');
    }
    final r = await _getJson(
      '/api/prekeys/${Uri.encodeComponent(peerId)}',
      token: token,
    );
    return r;
  }

  void dispose() => _client.close();
}

/// Ergebnis einer Auth-Operation (Tokens + userId).
class AuthResult {
  AuthResult({required this.accessToken, required this.refreshToken, this.userId});
  final String accessToken;
  final String refreshToken;
  final String? userId;

  factory AuthResult.fromJson(Map<String, dynamic> json, {bool hasUserId = true}) => AuthResult(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        userId: hasUserId ? json['userId'] as String? : null,
      );
}

/// ICE-Server-Konfiguration vom Server (inkl. signierter TURN-Credentials).
class IceConfig {
  IceConfig({required this.iceServers, this.ttlSeconds});
  final List<dynamic> iceServers;
  final int? ttlSeconds;

  factory IceConfig.fromJson(Map<String, dynamic> json) => IceConfig(
        iceServers: (json['iceServers'] as List?) ?? [],
        ttlSeconds: json['ttlSeconds'] as int?,
      );
}

/// API-Fehler mit Statuscode (z. B. 401 für Token-Rotation).
class ApiException implements Exception {
  ApiException({required this.statusCode, required this.message});
  final int statusCode;
  final String message;
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Provider für den [ApiClient] (mit Zertifikat-Pinning). Zentral definiert,
/// damit ihn sowohl [WebRTCService] als auch [PreKeyService] nutzen können,
/// ohne dass sich die Service-Dateien gegenseitig importieren müssen.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

