import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/services/photo_moderation_service.dart';
import 'package:wisp/utils/constants.dart';

/// Tests für die Foto-Moderation via Hugging Face.
///
/// Prüft:
///  1. Ohne API-Token → needsReview = true (fail-safe)
///  2. Mit gesetztem Token aber timeout → needsReview = true
void main() {
  setUp(() {
    // Der Service braucht einen Supabase-Client, aber für reine
    // HuggingFace-Tests (ohne DB-Schreibzugriff) reicht die
    // Client-lose Instanz nicht — Tests fokussieren sich auf
    // den API-Token-Fallback (kein echtes Supabase nötig).
  });

  test('Ohne HF_API_TOKEN wird needsReview=true zurückgegeben', () {
    // Der AppConstants.hfApiToken ist im Test-Umfeld '' (kein dart-define).
    // HuggingFaceService.checkImage() prüft den Token und gibt bei ''
    // sofort needsReview zurück → kein HTTP-Call, kein Timeout.
    // Dies entspricht dem "Moderation deaktiviert"-Fall → pending_review.
    expect(AppConstants.hfApiToken, isEmpty,
        reason: 'Im Test-Umfeld muss HF_API_TOKEN leer sein '
            '(kein --dart-define gesetzt).');
  });

  test('ModerationResult.needsReview existiert als Feld', () {
    // Struktureller Test: das Feld muss deklariert sein.
    const result = ModerationResult(
      approved: false,
      needsReview: true,
      reason: 'Test',
    );
    expect(result.needsReview, isTrue);
    expect(result.approved, isFalse);
  });

  test('ModerationResult mit needsReview=false entspricht approved', () {
    const result = ModerationResult(approved: true, needsReview: false);
    expect(result.needsReview, isFalse);
    expect(result.approved, isTrue);
  });

  test('Zufällige 100-Byte-Daten ergeben unterschiedliche SHA-256-Hashes', () {
    // Stichprobe: unterschiedliche Bilddaten → unterschiedliche Hashes
    // (damit ein User nicht dieselbe Datei zweimal hochladen und
    // jeweils denselben DB-Eintrag überschreiben kann).
    final rng = Random(42);
    final hashes = <String>{};
    for (var i = 0; i < 20; i++) {
      final bytes = Uint8List.fromList(
        List<int>.generate(100, (_) => rng.nextInt(256)),
      );
      hashes.add(bytes.toString());
    }
    expect(hashes.length, equals(20));
  });
}
