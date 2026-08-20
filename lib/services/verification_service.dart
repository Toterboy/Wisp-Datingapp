import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';

import 'package:wisp/services/secure_hive.dart';
import 'package:wisp/services/supabase_service.dart';

/// Model für das Verifizierungs-Video.
class VerificationVideo {
  const VerificationVideo({
    required this.filePath,
    required this.recordedAt,
    required this.durationSeconds,
    this.challengeText,
    this.challengeGesture,
    this.location,
    this.isVerified = false,
    this.faceEmbedding, // Für späteren Gesichtserkennungs-Abgleich
  });

  /// Lokaler Dateipfad des Videos.
  final String filePath;

  /// Aufnahmezeitpunkt.
  final DateTime recordedAt;

  /// Dauer in Sekunden.
  final int durationSeconds;

  /// Zufälliger Text, den der Nutzer sprechen musste (Liveness).
  final String? challengeText;

  /// Zufällige Geste, die der Nutzer machen musste (z. B. "Zunge raus", "Blinzeln").
  final String? challengeGesture;

  /// GPS-Position bei Aufnahme (für Massen-Fake-Erkennung).
  final Position? location;

  /// Ob das Video manuell/automatisch verifiziert wurde.
  final bool isVerified;

  /// Gesichtseinbettung (Embedding) für späteren Abgleich mit Profilbildern.
  /// In Produktion: Vektor aus FaceNet/ML-Kit. Für Prototyp: null.
  final List<double>? faceEmbedding;

  VerificationVideo copyWith({
    String? filePath,
    DateTime? recordedAt,
    int? durationSeconds,
    String? challengeText,
    String? challengeGesture,
    Position? location,
    bool? isVerified,
    List<double>? faceEmbedding,
  }) {
    return VerificationVideo(
      filePath: filePath ?? this.filePath,
      recordedAt: recordedAt ?? this.recordedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      challengeText: challengeText ?? this.challengeText,
      challengeGesture: challengeGesture ?? this.challengeGesture,
      location: location ?? this.location,
      isVerified: isVerified ?? this.isVerified,
      faceEmbedding: faceEmbedding ?? this.faceEmbedding,
    );
  }

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'recordedAt': recordedAt.toIso8601String(),
        'durationSeconds': durationSeconds,
        'challengeText': challengeText,
        'challengeGesture': challengeGesture,
        'location': location != null
            ? {'lat': location!.latitude, 'lng': location!.longitude}
            : null,
        'isVerified': isVerified,
        'faceEmbedding': faceEmbedding,
      };

  factory VerificationVideo.fromJson(Map<String, dynamic> json) {
    return VerificationVideo(
      filePath: json['filePath'] as String,
      recordedAt: DateTime.parse(json['recordedAt'] as String),
      durationSeconds: json['durationSeconds'] as int,
      challengeText: json['challengeText'] as String?,
      challengeGesture: json['challengeGesture'] as String?,
      location: json['location'] == null
          ? null
          : Position(
              latitude: (json['location']['lat'] as num).toDouble(),
              longitude: (json['location']['lng'] as num).toDouble(),
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              headingAccuracy: 0,
              altitudeAccuracy: 0,
            ),
      isVerified: json['isVerified'] as bool? ?? false,
      faceEmbedding: (json['faceEmbedding'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
    );
  }
}

/// Challenge-Typen für Liveness-Check.
enum VerificationChallengeType {
  /// Zufällige Zahl/Ziffernfolge vorlesen.
  speakNumber,
  /// Bestimmte Geste machen (z. B. blinzeln, Zunge raus).
  makeGesture,
  /// Kopf drehen (links/rechts).
  turnHead,
  /// Lächeln.
  smile,
}

/// Service für Video-Verifizierung.
class VerificationService {
  static const String _boxName = 'verification_videos';
  static const int _minDurationSeconds = 5;
  static const int _maxDurationSeconds = 15;

  /// Minimale zulässige Aufnahmedauer in Sekunden.
  static int get minDurationSeconds => _minDurationSeconds;

  /// Maximale zulässige Aufnahmedauer in Sekunden.
  static int get maxDurationSeconds => _maxDurationSeconds;

  late Box<VerificationVideo> _box;
  bool _initialized = false;

  /// Verfügbare Challenges für Liveness-Check.
  static const List<VerificationChallengeType> _challengeTypes = [
    VerificationChallengeType.speakNumber,
    VerificationChallengeType.makeGesture,
    VerificationChallengeType.turnHead,
    VerificationChallengeType.smile,
  ];

  static const Map<VerificationChallengeType, String> _challengeDescriptions = {
    VerificationChallengeType.speakNumber: 'Sage die angezeigte Zahl laut vor.',
    VerificationChallengeType.makeGesture: 'Mache die angezeigte Geste (z. B. Zunge raus, blinzeln).',
    VerificationChallengeType.turnHead: 'Drehe den Kopf langsam nach links und rechts.',
    VerificationChallengeType.smile: 'Lächle kurz in die Kamera.',
  };

  /// Initialisiert den Service.
  Future<void> initialize() async {
    if (_initialized) return;
    // AES-verschlüsselt (GPS-Metadaten + Verifizierungsstatus, s. SecureHive).
    _box = await SecureHive.instance.openBox<VerificationVideo>(_boxName);
    _initialized = true;
    // Cleanup-Policy (Audit N2): Abgelaufene Videos/Dateien entfernen –
    // passiert im Hintergrund, blockiert die Initialisierung nicht.
    unawaited(_purgeExpired());
  }

  /// Aufbewahrungsdauer für Verifizierungs-Videos und ihre Metadaten.
  /// Nach Ablauf werden Datei und Hive-Eintrag gelöscht (DSGVO-
  /// Datenminimierung; ein Video wird i. d. R. innerhalb weniger Stunden
  /// geprüft).
  static const Duration _retention = Duration(days: 7);

  /// Entfernt abgelaufene Verifizierungs-Videos:
  /// 1. Hive-Einträge, deren recordedAt älter als [_retention] ist,
  /// 2. Dateien `verification_*` im Temp-Verzeichnis (auch verwaiste, deren
  ///    Box-Eintrag bereits fehlt).
  Future<void> _purgeExpired() async {
    try {
      final cutoff = DateTime.now().subtract(_retention);

      // 1) Box-Einträge + zugehörige Dateien.
      final expired = <String>[];
      for (final key in _box.keys) {
        final video = _box.get(key);
        if (video == null) continue;
        if (video.recordedAt.isBefore(cutoff)) {
          expired.add(key as String);
          final file = File(video.filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
      if (expired.isNotEmpty) {
        await _box.deleteAll(expired);
      }

      // 2) Verwaiste Dateien im Temp-Verzeichnis.
      final dir = await getTemporaryDirectory();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith('verification_') || !name.endsWith('.mp4')) {
          continue;
        }
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (e) {
      // Cleanup ist Best-Effort – darf Initialisierung/Nutzung nie brechen.
      if (kDebugMode) {
        debugPrint('[Verification] Cleanup fehlgeschlagen: $e');
      }
    }
  }

  /// Generiert eine zufällige Challenge für den Nutzer.
  ///
  /// Verwendet Random.secure() (Audit M8): Die frühere Uhrzeit-Modulo-
  /// Variante war vorhersagbar und hätte vorab vorbereitet werden können.
  (VerificationChallengeType, String) generateChallenge() {
    final type =
        _challengeTypes[_secureRandom.nextInt(_challengeTypes.length)];
    String challengeData;

    switch (type) {
      case VerificationChallengeType.speakNumber:
        final number =
            (1000 + _secureRandom.nextInt(9000)).toString();
        challengeData = number;
        break;
      case VerificationChallengeType.makeGesture:
        const gestures = ['Zunge rausstrecken', 'Einmal blinzeln', 'Augenbrauen hochziehen'];
        challengeData = gestures[_secureRandom.nextInt(gestures.length)];
        break;
      case VerificationChallengeType.turnHead:
        challengeData =
            _secureRandom.nextBool() ? 'links und rechts' : 'rechts und links';
        break;
      case VerificationChallengeType.smile:
        challengeData = 'lächeln';
        break;
    }

    return (type, challengeData);
  }

  static final Random _secureRandom = Random.secure();

  /// Holt die Anzeigetexte für eine Challenge.
  String getChallengeDescription(VerificationChallengeType type, String challengeData) {
    final base = _challengeDescriptions[type]!;
    return '$base\n\nDeine Aufgabe: "$challengeData"';
  }

  /// Startet die Video-Aufnahme mit der Frontkamera.
  ///
  /// Gibt den Pfad zur aufgenommenen Datei zurück.
  Future<String?> recordVerificationVideo({
    required CameraController cameraController,
    required VerificationChallengeType challengeType,
    required String challengeData,
    int maxDurationSeconds = _maxDurationSeconds,
  }) async {
    if (!cameraController.value.isInitialized) {
      throw StateError('Kamera nicht initialisiert');
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/verification_${DateTime.now().millisecondsSinceEpoch}.mp4';

    try {
      await cameraController.startVideoRecording();
      await Future.delayed(Duration(seconds: maxDurationSeconds));
      final file = await cameraController.stopVideoRecording();

      // Datei an endgültigen Ort verschieben
      await file.saveTo(filePath);
      return filePath;
    } catch (e) {
      debugPrint('[Verification] Aufnahmefehler: $e');
      return null;
    }
  }

  /// Speichert das fertige Verifizierungs-Video mit Metadaten.
  Future<VerificationVideo> saveVerificationVideo({
    required String filePath,
    required VerificationChallengeType challengeType,
    required String challengeData,
    Position? location,
  }) async {
    final video = VerificationVideo(
      filePath: filePath,
      recordedAt: DateTime.now(),
      durationSeconds: _maxDurationSeconds,
      challengeText: challengeType == VerificationChallengeType.speakNumber ? challengeData : null,
      challengeGesture: challengeType != VerificationChallengeType.speakNumber ? challengeData : null,
      location: location,
    );

    await _box.put(filePath, video);
    return video;
  }

  /// Holt das Verifizierungs-Video des aktuellen Nutzers.
  VerificationVideo? getVerificationVideo() {
    if (_box.isEmpty) return null;
    return _box.values.firstWhere(
      (v) => v.filePath.contains('verification_'),
      orElse: () => _box.values.first,
    );
  }

  /// Markiert das Video als verifiziert (nach manueller/automatischer Prüfung).
  Future<void> markAsVerified(String filePath) async {
    final video = _box.get(filePath);
    if (video != null) {
      await _box.put(filePath, video.copyWith(isVerified: true));
    }
  }

  /// Löscht das Video (z. B. bei erneuter Verifizierung).
  Future<void> deleteVideo(String filePath) async {
    await _box.delete(filePath);
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Prüft, ob der Nutzer bereits verifiziert ist.
  ///
  /// HINWEIS (Audit M3): Rein lokaler UX-Zustand – manipulierbar und ohne
  /// serverseitige Bedeutung. Authoritative Quelle ist
  /// `profiles.is_verified` (nur durch Admins/Edge Functions setzbar,
  /// Migration 040/verify-account).
  bool get isVerified {
    final video = getVerificationVideo();
    return video?.isVerified == true;
  }

  /// Fordert die serverseitige Verifizierung an (Edge Function
  /// `verify-account`).
  ///
  /// Seit Audit K2 ist die Funktion ADMIN-ONLY: Der Client kann
  /// `is_verified` nicht mehr selbst setzen. Dieser Aufruf meldet den
  /// Verifizierungswunsch; die Freigabe erfolgt nach manueller Prüfung
  /// durch einen Admin. Rückgabe ist daher aus Client-Sicht i. d. R.
  /// `false` (kein automatischer Verifizierungs-Erfolg mehr).
  Future<bool> verifyAccount() async {
    if (!SupabaseService.isInitialized) return false;

    try {
      final response = await SupabaseService.client.functions.invoke(
        'verify-account',
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final success = data['updated'] as bool? ?? false;
        if (success) {
          markAsVerified(getVerificationVideo()?.filePath ?? '');
        }
        return success;
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VerificationService] Error: $e');
      }
      return false;
    }
  }

  void dispose() {
    _box.close();
  }
}

/// Provider für den VerificationService.
final verificationServiceProvider = Provider<VerificationService>((ref) {
  final service = VerificationService();
  Future.microtask(() => service.initialize());
  ref.onDispose(service.dispose);
  return service;
});