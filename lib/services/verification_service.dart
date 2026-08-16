import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';

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
    _box = await Hive.openBox<VerificationVideo>(_boxName);
    _initialized = true;
  }

  /// Generiert eine zufällige Challenge für den Nutzer.
  (VerificationChallengeType, String) generateChallenge() {
    final type = _challengeTypes[DateTime.now().millisecondsSinceEpoch % _challengeTypes.length];
    String challengeData;

    switch (type) {
      case VerificationChallengeType.speakNumber:
        final number = (1000 + DateTime.now().millisecondsSinceEpoch % 9000).toString();
        challengeData = number;
        break;
      case VerificationChallengeType.makeGesture:
        const gestures = ['Zunge rausstrecken', 'Einmal blinzeln', 'Augenbrauen hochziehen'];
        challengeData = gestures[DateTime.now().millisecondsSinceEpoch % gestures.length];
        break;
      case VerificationChallengeType.turnHead:
        challengeData = DateTime.now().millisecondsSinceEpoch % 2 == 0 ? 'links und rechts' : 'rechts und links';
        break;
      case VerificationChallengeType.smile:
        challengeData = 'lächeln';
        break;
    }

    return (type, challengeData);
  }

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
  bool get isVerified {
    final video = getVerificationVideo();
    return video?.isVerified == true;
  }

  /// Ruft die Supabase Edge Function `verify-account` auf, um die
  /// Video-Verifizierung serverseitig abzuschließen.
  ///
  /// Der Supabase-Client sendet den aktuellen Session-Token automatisch im
  /// Authorization-Header, sodass die serverseitige JWT-Prüfung greift.
  Future<bool> verifyAccount() async {
    if (!SupabaseService.isInitialized) return false;

    try {
      final response = await SupabaseService.client.functions.invoke(
        'verify-account',
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final success = data['success'] as bool? ?? false;
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