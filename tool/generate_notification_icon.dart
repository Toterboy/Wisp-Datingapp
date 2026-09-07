import 'dart:io';

import 'package:image/image.dart' as img;

/// Erzeugt das Android-Benachrichtigungs-Icon (weisse Silhouette mit
/// Transparenz) aus dem Wisp-Logo.
///
/// Android verlangt fuer Statusleisten-Icons ein alpha-maskiertes,
/// einfarbig (weiss) Asset - farbige Logos erscheinen als weisser Punkt.
/// Output: android/app/src/main/res/drawable/notification_icon.png (96px).
///
/// Ausfuehren: dart run tool/generate_notification_icon.dart
void main(List<String> args) {
  final sourcePath = args.isNotEmpty
      ? args[0]
      : 'assets/images/wispdating_icon_base.png';
  final bytes = File(sourcePath).readAsBytesSync();
  final src = img.decodePng(bytes);
  if (src == null) {
    stderr.writeln('Konnte $sourcePath nicht dekodieren.');
    exit(1);
  }

  var work = src;
  if (work.width != 96 || work.height != 96) {
    work = img.copyResize(
      work,
      width: 96,
      height: 96,
      interpolation: img.Interpolation.average,
    );
  }
  // WICHTIG: Sicherstellen, dass das Bild einen Alpha-Kanal hat. Ohne
  // numChannels: 4 (bzw. bei opaken Quellen) entstaende ein volles 96x96
  // weisses Quadrat -> Statusleiste zeigt ein weisses VIERECK.
  if (work.numChannels < 4) {
    work = work.convert(numChannels: 4);
  }

  // Vollstaendig opake Quelle (alpha ueberall 255)? Dann gibt es keine
  // Silhouette - Alpha aus der Luminanz ableiten: dunkle Pixel (Badge/
  // Schriftzug) werden opak weiss, helle Flaechen transparent.
  var hasTransparency = false;
  for (final p in work) {
    if (p.a < 250) {
      hasTransparency = true;
      break;
    }
  }
  for (var y = 0; y < work.height; y++) {
    for (var x = 0; x < work.width; x++) {
      final p = work.getPixel(x, y);
      if (hasTransparency) {
        // Alpha-Maske behalten => Silhouette.
        work.setPixelRgba(x, y, 255, 255, 255, p.a);
      } else {
        // Luminanz-Fallback: 0.2126 R + 0.7152 G + 0.0722 B.
        final lum =
            0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
        final alpha = (255 - lum).round().clamp(0, 255);
        work.setPixelRgba(x, y, 255, 255, 255, alpha);
      }
    }
  }

  const outDir = 'android/app/src/main/res/drawable';
  Directory(outDir).createSync(recursive: true);
  final out = File('$outDir/notification_icon.png');
  out.writeAsBytesSync(img.encodePng(work));
  stdout.writeln('Geschrieben: $out (${work.width}x${work.height})');
}
