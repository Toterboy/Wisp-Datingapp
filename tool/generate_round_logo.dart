import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Erzeugt aus dem transparenten Foreground-Badge ein RUNDES Logo
/// (Badge-Inhalt in einen Kreis maskiert, Ecken transparent) und schreibt
/// es als `assets/images/wisp_icon_round.png` sowie als natives Splash-Bild
/// `splash_raw.png` in alle Android-Dichteordner.
///
/// Aufruf: dart run tool/generate_round_logo.dart
void main() {
  final fg = img.decodePng(
    File('assets/images/wisp_icon_foreground.png').readAsBytesSync(),
  );
  if (fg == null) {
    throw Exception('wisp_icon_foreground.png konnte nicht geladen werden');
  }

  // Bounding-Box des sichtbaren Badges ermitteln.
  var minX = fg.width;
  var minY = fg.height;
  var maxX = 0;
  var maxY = 0;
  for (final p in fg) {
    if (p.a > 8) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }

  final badgeW = maxX - minX + 1;
  final badgeH = maxY - minY + 1;
  final size = badgeW > badgeH ? badgeW : badgeH;
  final center = size / 2.0;
  final radius = size / 2.0 - 0.5;

  final out = img.Image(width: size, height: size);
  for (final p in out) {
    final dx = p.x + 0.5 - center;
    final dy = p.y + 0.5 - center;
    final dist = dx * dx + dy * dy;
    if (dist <= radius * radius) {
      final src = fg.getPixel(minX + p.x, minY + p.y);
      p.setRgba(src.r, src.g, src.b, src.a);
    }
  }
  // Sanfte Kante: Pixel knapp innerhalb des Radius leicht weich zeichnen.
  for (final p in out) {
    if (p.a == 0) continue;
    final dx = p.x + 0.5 - center;
    final dy = p.y + 0.5 - center;
    final dist = sqrtSafe(dx * dx + dy * dy);
    final edge = radius - dist;
    if (edge < 1.5) {
      final alpha = (p.a * (edge.clamp(0.0, 1.5) / 1.5)).round();
      p.a = alpha.clamp(0, 255);
    }
  }

  final roundLogo = img.encodePng(out);
  File('assets/images/wisp_icon_round.png').writeAsBytesSync(roundLogo);

  final densities = <String>[
    'android/app/src/main/res/drawable',
    'android/app/src/main/res/drawable-hdpi',
    'android/app/src/main/res/drawable-mdpi',
    'android/app/src/main/res/drawable-night',
    'android/app/src/main/res/drawable-night-hdpi',
    'android/app/src/main/res/drawable-night-mdpi',
    'android/app/src/main/res/drawable-night-v21',
    'android/app/src/main/res/drawable-night-xhdpi',
    'android/app/src/main/res/drawable-night-xxhdpi',
    'android/app/src/main/res/drawable-night-xxxhdpi',
    'android/app/src/main/res/drawable-v21',
    'android/app/src/main/res/drawable-xhdpi',
    'android/app/src/main/res/drawable-xxhdpi',
    'android/app/src/main/res/drawable-xxxhdpi',
  ];
  for (final dir in densities) {
    File('$dir/splash_raw.png').writeAsBytesSync(roundLogo);
  }

  // ignore: avoid_print
  print('Rundes Logo erzeugt: ${size}x$size px (${densities.length + 1} Dateien)');
}

double sqrtSafe(double v) => v <= 0 ? 0 : math.sqrt(v);
