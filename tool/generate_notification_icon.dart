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
      : 'assets/images/wisp_icon_base.png';
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

  // Alle Pixel auf weiss stellen, Alpha-Maske behalten => Silhouette.
  for (var y = 0; y < work.height; y++) {
    for (var x = 0; x < work.width; x++) {
      final p = work.getPixel(x, y);
      work.setPixelRgba(x, y, 255, 255, 255, p.a);
    }
  }

  const outDir = 'android/app/src/main/res/drawable';
  Directory(outDir).createSync(recursive: true);
  final out = File('$outDir/notification_icon.png');
  out.writeAsBytesSync(img.encodePng(work));
  stdout.writeln('Geschrieben: $out (${work.width}x${work.height})');
}
