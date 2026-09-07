// Verifiziert das echte NSFW-Modell (Windows-Desktop): lädt die Session und
// führt eine echte Inferenz aus. Deckt Lade-/Form-Fehler auf, die in der
// App stillschweigend zu `null` führen würden (dann kein NSFW-Dialog!).
import 'package:flutter/services.dart' show Uint8List;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wisp/services/image_safety_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NSFW-Modell lädt und klassifiziert (echte Inferenz)', () async {
    final available = await ImageSafetyService.instance.ensureSession();
    // ignore: avoid_print
    print('ensureSession -> $available');
    expect(available, isTrue,
        reason: 'Modell muss gebündelt und ladbar sein - sonst läuft der '
            'NSFW-Check in der App stillschweigend nicht.');

    // Testbild: farbiger Verlauf (kein NSFW-Inhalt).
    final im = img.Image(width: 300, height: 300);
    for (var y = 0; y < 300; y++) {
      for (var x = 0; x < 300; x++) {
        im.setPixelRgba(x, y, x % 256, y % 256, (x + y) % 256, 255);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(im, quality: 90));

    final result = await ImageSafetyService.instance.classifyImage(bytes);
    // ignore: avoid_print
    print('classifyImage -> $result');
    expect(result, isNotNull,
        reason: 'Inferenz muss funktionieren - null bedeutet stiller '
            'Fallback ohne Dialog.');
    // ignore: avoid_print
    print('nsfl=${result!.nsfl.toStringAsFixed(3)} '
        'nsfw=${result.nsfw.toStringAsFixed(3)} '
        'sfw=${result.sfw.toStringAsFixed(3)} top=${result.topLabel}');
    final sum = result.nsfl + result.nsfw + result.sfw;
    // ignore: avoid_print
    print('Summe: ${sum.toStringAsFixed(3)}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
