import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Audit M-21: Explizites EXIF-/Metadaten-Scrubbing vor Upload/Versand.
///
/// Bisher war das Strippen nur eine implizite Folge der Re-Encoding-
/// Parameter von image_picker/image_cropper. Ein Plugin-Update oder ein
/// neuer Codepfad hätte GPS-Koordinaten, Geräteinfos und Zeitstempel
/// aus den Original-Bildern an Matches/Bug-Reports durchgereicht.
///
/// Diese Funktion dekodiert das Bild und encodiert es NEU - dabei gehen
/// sämtliche Metadaten verloren. Rückgabe `null` = nicht dekodierbar
/// (fail-closed: Der Aufrufer sendet dann NICHTS statt der Originalbytes).
///
/// FREEZE-FIX (v0.8.1): Decode + Encode eines Vollbild-Fotos im pure-Dart
/// `image`-Package dauert auf dem Handy MEHRERE SEKUNDEN. Bisher lief das
/// synchron im UI-Thread (App "hängt sich auf", Android-ANR beim
/// Chat-Bild-Versand/Profilbild-Pick). Jetzt läuft die komplette
/// Verarbeitung in einem Hintergrund-Isolate.
Future<Uint8List?> stripImageMetadata(
  Uint8List bytes, {
  int jpegQuality = 88,
}) {
  return compute(_stripSync, (bytes, jpegQuality));
}

/// Reine (isolate-sichere) Arbeitsfunktion ohne Flutter-Bezug.
Uint8List? _stripSync((Uint8List, int) args) {
  final (bytes, jpegQuality) = args;
  try {
    final decoder = img.findDecoderForData(bytes);
    if (decoder == null) {
      return null; // Kein bekanntes Bildformat - verweigere Verarbeitung.
    }
    final image = decoder.decode(bytes);
    if (image == null) {
      return null; // Dekodierung fehlgeschlagen - verweigere Verarbeitung.
    }

    // Format beibehalten: JPEG bleibt JPEG (Fotos), alles andere PNG.
    final isJpegSource = bytes.length > 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;

    final encoded = isJpegSource
        ? img.encodeJpg(image, quality: jpegQuality)
        : img.encodePng(image);

    return Uint8List.fromList(encoded);
  } catch (e) {
    return null; // Scrubbing fehlgeschlagen - fail-closed.
  }
}
