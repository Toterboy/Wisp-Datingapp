import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Erzeugt aus dem runden WispDating-Logos
/// (`assets/images/wispdating_logo_round.png`):
///
///  1. `splash_raw.png` (day + night) in allen Android-Dichteordnern.
///     Night: Hintergrund ~15 % abgedunkelt, weiße Schrift bleibt weiß.
///  2. `wisp_icon_foreground.png` – Adaptive-Icon-Foreground (Safe-Zone).
///  3. `drawable/notification_icon.png` – 96 px, weiß + Alpha (Android-
///     Statusleiste): helle Elemente des Logos werden weiß, der Rest
///     transparent. Fällt auf eine volle Kreissilhouette zurück, wenn zu
///     wenige helle Pixel gefunden werden.
///
/// Aufruf: dart run tool/generate_branding.dart
void main() {
  const roundPath = 'assets/images/wispdating_logo_round.png';
  final src = img.decodePng(File(roundPath).readAsBytesSync());
  if (src == null) throw Exception('$roundPath konnte nicht gelesen werden');

  // ---- 1) Splash day + night -------------------------------------------
  final splashDay = img.copyResize(
    src,
    width: 670,
    height: 670,
    interpolation: img.Interpolation.cubic,
  );
  final splashBytes = img.encodePng(splashDay);

  final night = img.Image.from(splashDay);
  for (final p in night) {
    if (p.a == 0) continue;
    final isNearWhite = p.r > 235 && p.g > 235 && p.b > 235;
    if (!isNearWhite) {
      p.setRgba(
        (p.r * 0.85).round(),
        (p.g * 0.85).round(),
        (p.b * 0.85).round(),
        p.a,
      );
    }
  }
  final splashNightBytes = img.encodePng(night);

  final dayDirs = <String>[
    'android/app/src/main/res/drawable',
    'android/app/src/main/res/drawable-hdpi',
    'android/app/src/main/res/drawable-mdpi',
    'android/app/src/main/res/drawable-v21',
    'android/app/src/main/res/drawable-xhdpi',
    'android/app/src/main/res/drawable-xxhdpi',
    'android/app/src/main/res/drawable-xxxhdpi',
  ];
  for (final dir in dayDirs) {
    File('$dir/splash_raw.png').writeAsBytesSync(splashBytes);
  }
  final nightDirs = <String>[
    'android/app/src/main/res/drawable-night',
    'android/app/src/main/res/drawable-night-hdpi',
    'android/app/src/main/res/drawable-night-mdpi',
    'android/app/src/main/res/drawable-night-v21',
    'android/app/src/main/res/drawable-night-xhdpi',
    'android/app/src/main/res/drawable-night-xxhdpi',
    'android/app/src/main/res/drawable-night-xxxhdpi',
  ];
  for (final dir in nightDirs) {
    File('$dir/splash_raw.png').writeAsBytesSync(splashNightBytes);
  }

  // ---- 2) Adaptive-Icon-Foreground (Safe-Zone ~66 %) --------------------
  const fgSize = 1024;
  final fgContent = (fgSize * 0.66).round();
  final fgScaled = img.copyResize(
    src,
    width: fgContent,
    height: fgContent,
    interpolation: img.Interpolation.cubic,
  );
  final fg = img.Image(width: fgSize, height: fgSize);
  final fgOff = (fgSize - fgContent) ~/ 2;
  for (final p in fgScaled) {
    fg.setPixel(p.x + fgOff, p.y + fgOff, p);
  }
  File('assets/images/wisp_icon_foreground.png')
      .writeAsBytesSync(img.encodePng(fg));

  // ---- 3) Notification-Icon (weiß + Alpha, 96 px) -----------------------
  const nSize = 96;
  final n = img.Image(width: nSize, height: nSize);
  var whitePixels = 0;
  for (final p in n) {
    final sx = (p.x * src.width / nSize).floor().clamp(0, src.width - 1);
    final sy = (p.y * src.height / nSize).floor().clamp(0, src.height - 1);
    final s = src.getPixel(sx, sy);
    if (s.a.toInt() < 40) continue; // außen transparent
    final lum =
        0.299 * s.r.toInt() + 0.587 * s.g.toInt() + 0.114 * s.b.toInt();
    // Helle Elemente (Schriftzug/Swirl) -> weiß; weiche Kante via Rampe.
    final t = ((lum - 150) / 70).clamp(0.0, 1.0);
    if (t > 0) {
      p.setRgba(255, 255, 255, (t * 255).round());
      whitePixels++;
    }
  }
  // Fallback: zu wenig hell -> volle Kreissilhouette.
  if (whitePixels < 400) {
    for (final p in n) {
      final dx = p.x + 0.5 - nSize / 2;
      final dy = p.y + 0.5 - nSize / 2;
      p.setRgba(255, 255, 255, 255);
      if (math.sqrt(dx * dx + dy * dy) > nSize / 2 - 2) p.a = 0;
    }
  }
  File('android/app/src/main/res/drawable/notification_icon.png')
      .writeAsBytesSync(img.encodePng(n));

  stdout.writeln('Branding erzeugt: Splash day/night (${dayDirs.length + nightDirs.length} '
      'Dateien), Foreground, Notification-Icon (weiss=$whitePixels px)');
}
