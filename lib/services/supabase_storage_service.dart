import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/supabase_service.dart';

/// Service für private Avatar-Speicherung in Supabase Storage.
///
/// WICHTIG:
/// - Der Bucket `avatars` ist privat (public = false).
/// - Clientseitig wird NUR der Pfad `{userId}/avatar.jpg` verwendet.
/// - Der Upload nutzt die standard PostgREST-Insert-Route auf `storage.objects`.
/// - Anzeige erfolgt AUSSCHLIESSLICH über temporäre signierte URLs
///   (`createSignedUrl`), nie über öffentliche URLs.
class SupabaseStorageService {
  SupabaseStorageService(this._client);

  final SupabaseClient _client;

  User? get _currentUser => SupabaseService.currentUser;

  static const String _bucket = 'avatars';
  static const String _fileName = 'avatar.jpg';
  static const int _signedUrlExpirySeconds = 3600;

  /// Lädt eine Chat-Media-Datei (Bild, Sprache) in den Storage hoch.
  ///
  /// Speichert unter `{userId}/chat/{timestamp}.{ext}`.
  /// Gibt die signierte URL zurück, die direkt im Chat angezeigt werden kann.
  Future<String> uploadChatMedia(List<int> data, String fileExtension) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    // Pfad-Traversal/Injektion verhindern (Audit N1): Nur harmlose
    // Datei-Endungen erlauben, alles andere neutralisieren.
    final safeExtension =
        RegExp(r'^[A-Za-z0-9]{1,8}$').hasMatch(fileExtension)
            ? fileExtension.toLowerCase()
            : 'bin';

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$userId/chat/$timestamp.$safeExtension';
    if (kDebugMode) {
      log('[SupabaseStorageService] Upload chat media: '
          'bucket=$_bucket size=${data.length}');
    }

    await _client.storage.from(_bucket).uploadBinary(
          path,
          Uint8List.fromList(data),
        );

    final signedUrl = await _client.storage
        .from(_bucket)
        .createSignedUrl(path, _signedUrlExpirySeconds);

    return signedUrl;
  }

  /// Pfad für den aktuellen Nutzer: `{userId}/avatar.jpg`.
  String _avatarPathForUser(String userId) => '$userId/$_fileName';

  /// Lädt ein Avatar-Bild hoch.
  ///
  /// [data] sind die rohen Bild-Bytes.
  /// Der Pfad wird immer auf `{userId}/avatar.jpg` festgelegt.
  /// Gibt den Storage-Pfad zurück, unter dem das Bild gespeichert wurde.
  Future<String> uploadAvatar(List<int> data) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    final path = _avatarPathForUser(userId);
    if (kDebugMode) {
      log('[SupabaseStorageService] Upload avatar: bucket=$_bucket size=${data.length}');
    }

    await _client.storage.from(_bucket).uploadBinary(
          path,
          Uint8List.fromList(data),
        );

    return path;
  }

  /// Erzeugt eine temporäre signierte URL für den angegebenen Storage-Pfad.
  ///
  /// Gültigkeit: 3600 Sekunden. Die URL ist nur mit aktiver Session gültig.
  Future<String?> getSignedAvatarUrl(String path) async {
    if (kDebugMode) {
      log('[SupabaseStorageService] Request signed URL: bucket=$_bucket');
    }

    final result = await _client.storage
        .from(_bucket)
        .createSignedUrl(path, _signedUrlExpirySeconds);

    return result;
  }

  /// Löscht den aktuellen Avatar.
  Future<void> deleteAvatar() async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    final path = _avatarPathForUser(userId);
    if (kDebugMode) {
      log('[SupabaseStorageService] Delete avatar: bucket=$_bucket');
    }

    await _client.storage.from(_bucket).remove([path]);
  }

  /// Pfad der Intro-Audio-Datei: `{userId}/intro.m4a`.
  String _introPathForUser(String userId) => '$userId/intro.m4a';

  /// Lädt die Audio-Vorstellung hoch und gibt den Storage-Pfad zurück.
  Future<String> uploadIntroAudio(List<int> data) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    final path = _introPathForUser(userId);
    if (kDebugMode) {
      log('[SupabaseStorageService] Upload intro audio: bucket=$_bucket size=${data.length}');
    }

    await _client.storage.from(_bucket).uploadBinary(
          path,
          Uint8List.fromList(data),
        );

    return path;
  }

  /// Entfernt die Audio-Vorstellung.
  Future<void> deleteIntroAudio() async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    final path = _introPathForUser(userId);
    if (kDebugMode) {
      log('[SupabaseStorageService] Delete intro audio: bucket=$_bucket');
    }

    await _client.storage.from(_bucket).remove([path]);
  }
}

/// Provider für den [SupabaseStorageService].
final supabaseStorageServiceProvider = Provider<SupabaseStorageService>((ref) {
  return SupabaseStorageService(SupabaseService.client);
});
