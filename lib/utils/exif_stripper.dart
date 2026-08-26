import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
/// Audit M-21: Explizites EXIF-/Metadaten-Scrubbing vor Upload/Versand.
///
/// Bisher war das Strippen nur eine implizite Folge der Re-Encoding-
/// Parameter von image_picker/image_cropper. Ein Plugin-Update oder ein
/// neuer Codepfad hätte GPS-Koordinaten, Geräte-Serials und Zeitstempel
/// aus den Original-Bildern an Matches/Bug-Reports durchgereicht.
///
/// Diese Funktion dekodiert das Bild und encodiert es NEU - dabei gehen
/// sämtliche Metadaten verloren. Rückgabe `null` = nicht dekodierbar
/// (fail-closed: Der Aufrufer sendet dann NICHTS statt der Originalbytes).
Uint8List? stripImageMetadata(
  Uint8List bytes, {
  int jpegQuality = 88,
}) {
  try {
    final decoder = img.findDecoderForData(bytes);
    if (decoder == null) {
      debugPrint('[EXIF] Kein bekanntes Bildformat - verweigere Verarbeitung.');
      return null;
    }
    final image = decoder.decode(bytes);
    if (image == null) {
      debugPrint('[EXIF] Dekodierung fehlgeschlagen - verweigere Verarbeitung.');
      return null;
    }

    // Format beibehalten: JPEG bleibt JPEG (Fotos), alles andere PNG.
    final isJpegSource = bytes.length > 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;

    final encoded = isJpegSource
        ? img.encodeJpg(image, quality: jpegQuality)
        : img.encodePng(image);

    debugPrint('[EXIF] Metadaten entfernt (${bytes.length} -> ${encoded.length} Bytes).');
    return Uint8List.fromList(encoded);
  } catch (e) {
    debugPrint('[EXIF] Scrubbing fehlgeschlagen - fail-closed.');
    return null;
  }
}
