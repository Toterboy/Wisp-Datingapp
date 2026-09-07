import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/avatar_crypto.dart';
import 'package:wisp/services/supabase_service.dart';

/// Service für private Avatar-Speicherung in Supabase Storage.
///
/// WICHTIG:
/// - Der Bucket `avatars` ist privat (public = false).
/// - Clientseitig wird NUR der Pfad `{userId}/avatar.jpg` verwendet.
/// - Der Upload nutzt die standard PostgREST-Insert-Route auf `storage.objects`.
/// - Anzeige erfolgt über signierte URLs ODER (v0.8.1) verschlüsselt:
///   Profilbilder werden clientseitig AES-256-GCM verschlüsselt, bevor
///   sie den Server erreichen. Der Schlüssel steckt im `photos`-Eintrag
///   (`path|key|iv`), der Download läuft über [loadAvatarBytes] mit
///   lokaler Entschlüsselung.
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

  /// Lädt ein Avatar-Bild hoch (v0.8.1: AES-256-GCM-verschlüsselt).
  ///
  /// [data] sind die rohen Bild-Bytes. Sie werden VOR dem Upload
  /// verschlüsselt - der Server sieht nie das Klartext-Bild. Der Pfad
  /// bleibt `{userId}/avatar.jpg`; der Zufalls-Schlüssel wird im
  /// Rückgabewert (`path|key|iv`) mitgeführt und landet in
  /// `profiles.photos`. Alte (Klartext-)Avatare bleiben mit
  /// [loadAvatarBytes] lesbar (Fallback).
  Future<String> uploadAvatar(List<int> data) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    final enc = AvatarCrypto.encrypt(Uint8List.fromList(data));
    final path = _avatarPathForUser(userId);
    if (kDebugMode) {
      log('[SupabaseStorageService] Upload avatar (verschlüsselt): '
          'bucket=$_bucket size=${enc.cipher.length}');
    }

    // upsert: Erneutes Hochladen (neues Bild) ueberschreibt das alte -
    // ohne upsert wuerde der zweite Upload mit 409 scheitern.
    await _client.storage.from(_bucket).uploadBinary(
          path,
          enc.cipher,
          fileOptions: const FileOptions(upsert: true),
        );

    return AvatarCrypto.encodeRef(path, enc.keyB64, enc.ivB64);
  }

  /// Lädt ein Avatar herunter und entschlüsselt es lokal (v0.8.1).
  ///
  /// Akzeptiert sowohl verschlüsselte Einträge (`path|key|iv`) als auch
  /// Legacy-Klartext-Pfade. Liefert die BILD-BYTES (keine URL!) - der
  /// Aufrufer zeigt sie mit `Image.memory`/`MemoryImage` an.
  ///
  /// Performance (v0.8.1): Ergebnis wird pro Referenz IM SPEICHERER
  /// gecacht - Profil, Vorschau und QR-Screen laden ohne Wartezeit; der
  /// Cache-Key ist die komplette Referenz, ein neues Bild = neuer Key.
  static final Map<String, Uint8List> _avatarMemoryCache = {};

  Future<Uint8List?> loadAvatarBytes(String ref) async {
    final cached = _avatarMemoryCache[ref];
    if (cached != null) return cached;
    try {
      final parsed = AvatarCrypto.parseRef(ref);
      final path = parsed?.path ?? AvatarCrypto.pathOf(ref);
      final data =
          await _client.storage.from(_bucket).download(path);
      final result = parsed == null
          ? data // Legacy: Klartext.
          : AvatarCrypto.decrypt(data, parsed.key, parsed.iv);
      _avatarMemoryCache[ref] = result;
      return result;
    } catch (e) {
      if (kDebugMode) {
        log('[SupabaseStorageService] Avatar-Download/Entschlüsselung '
            'fehlgeschlagen: $e');
      }
      return null;
    }
  }

  /// Erzeugt eine temporäre signierte URL für den angegebenen Storage-Pfad.
  ///
  /// Gültigkeit: 3600 Sekunden. Die URL ist nur mit aktiver Session gültig.
  /// (NUR noch für Intro-Audio u. ä. - Profilbilder laufen über
  /// [loadAvatarBytes], weil sie verschlüsselt sind.)
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
          // upsert: Erneutes Hochladen (z. B. zweite Aufnahme in der
          // Einrichtung) ueberschreibt das alte Audio - ohne upsert
          // scheitert es mit StorageException 409 "Duplicate".
          fileOptions: const FileOptions(upsert: true),
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

  // =========================================================================
  // Verifizierungs-Video (privater Bucket, nur eigener Ordner per RLS).
  // =========================================================================

  static const _verificationBucket = 'verification-videos';

  /// Lädt das Verifizierungs-Video in den PRIVATEN Bucket und gibt den
  /// Storage-Pfad zurück (`{userId}/video.mp4`). Lesen kann die Datei nur
  /// der Eigentümer; Admins erhalten kurzlebige signierte URLs über die
  /// Edge Function `verification-media`.
  Future<String> uploadVerificationVideo(List<int> data) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }
    if (data.isEmpty) {
      throw AppException('Das Video ist leer.');
    }

    final path = '$userId/video.mp4';
    if (kDebugMode) {
      log('[SupabaseStorageService] Upload verification video: '
          'size=${data.length}');
    }

    await _client.storage.from(_verificationBucket).uploadBinary(
          path,
          Uint8List.fromList(data),
          fileOptions: const FileOptions(contentType: 'video/mp4'),
        );

    return path;
  }

  /// Entfernt das eigene Verifizierungs-Video (z. B. bei Abbruch).
  Future<void> deleteVerificationVideo() async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }
    await _client.storage.from(_verificationBucket).remove([
      '$userId/video.mp4',
    ]);
  }
}

/// Provider für den [SupabaseStorageService].
final supabaseStorageServiceProvider = Provider<SupabaseStorageService>((ref) {
  return SupabaseStorageService(SupabaseService.client);
});
