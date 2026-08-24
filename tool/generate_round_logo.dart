import 'dart:io';

import 'package:image/image.dart' as img;

/// Erzeugt alle Logos aus dem neuen WispDating-Basis-Icon
/// (`assets/images/wispdating_icon_base.png`):
///
///  1. `wisp_icon_round.png`          â€“ rundes App-Logo (Light + Dark nutzbar)
///     Das quadratische Artwork wird leicht eingezoomt, sodass die Ecken
///     des Rounded-Square sicher auÃŸerhalb des Kreises liegen (kein
///     "Ecken-Blitzen" am Rand), mit weicher Kante.
///  2. `wisp_icon_round_dark.png`     â€“ identisch, Hintergrund um ~12 %
///     abgedunkelt (weiÃŸe Design-Elemente bleiben weiÃŸ).
///  3. `wisp_icon_foreground.png`     â€“ Adaptive-Icon-Foreground
///     (Inhalt auf ~66 % Safe-Zone, transparenter Rand).
///  4. `splash_raw.png` in allen Android-Dichteordnern (day + night).
///
/// Aufruf: dart run tool/generate_round_logo.dart
void main(List<String> args) {
  const sourcePath = 'assets/images/wispdating_icon_base.png';
  final src = img.decodePng(File(sourcePath).readAsBytesSync());
  if (src == null) throw Exception('$sourcePath konnte nicht gelesen werden');

  // Bounding-Box der opaken Pixel (das PNG hat einen transparenten Rand).
  var minX = src.width, minY = src.height, maxX = 0, maxY = 0;
  for (final p in src) {
    if (p.a.toInt() > 20) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  final bw = maxX - minX + 1;
  final bh = maxY - minY + 1;
  final bboxSide = bw > bh ? bw : bh;

  // Auf Quadrat (laengere Seite) transparent padden, zentriert.
  final square = img.Image(width: bboxSide, height: bboxSide);
  final padX = (bboxSide - bw) ~/ 2;
  final padY = (bboxSide - bh) ~/ 2;
  for (final p in img.copyCrop(
    src,
    x: minX,
    y: minY,
    width: bw,
    height: bh,
  )) {
    square.setPixel(p.x + padX, p.y + padY, p);
  }

  // ---- 1+2) Rundes Logo (Light + Dark) ---------------------------------
  const outSize = 1024;
  // Zoom: Ecken des Rounded-Square sollen auÃŸerhalb des Kreises liegen.
  // Faktor 1.18 -> Eckabstand sicher auÃŸerhalb, Motiv bleibt vollstÃ¤ndig.
  final zoom = 1.18;
  final scaled = img.copyResize(
    square,
    width: (outSize * zoom).round(),
    height: (outSize * zoom).round(),
    interpolation: img.Interpolation.cubic,
  );
  final inset = (scaled.width - outSize) ~/ 2;
  final round = img.Image(width: outSize, height: outSize);
  final radius = outSize / 2.0 - 0.5;

  for (final p in round) {
    final dx = p.x + 0.5 - outSize / 2;
    final dy = p.y + 0.5 - outSize / 2;
    final distSq = dx * dx + dy * dy;
    if (distSq <= radius * radius) {
      final s = scaled.getPixel(
        (p.x + inset).clamp(0, scaled.width - 1),
        (p.y + inset).clamp(0, scaled.height - 1),
      );
      p.setRgba(s.r, s.g, s.b, s.a);
    }
  }

  // Weiche Kante (1.5 px Alpha-Falloff).
  for (final p in round) {
    if (p.a == 0) continue;
    final dx = p.x + 0.5 - outSize / 2;
    final dy = p.y + 0.5 - outSize / 2;
    final edge = radius - _dist(dx, dy);
    if (edge < 1.5) {
      p.a = (p.a * (edge.clamp(0.0, 1.5) / 1.5)).round().clamp(0, 255);
    }
  }

  File('assets/images/wisp_icon_round.png')
      .writeAsBytesSync(img.encodePng(round));

  // Dark: Hintergrund-Motive ~12 % abgedunkelt; nahe-weiÃŸe Design-Elemente
  // (Schriftzug/Herz) bleiben weiÃŸ.
  final dark = img.Image.from(round);
  for (final p in dark) {
    if (p.a == 0) continue;
    final isNearWhite = p.r > 235 && p.g > 235 && p.b > 235;
    if (!isNearWhite) {
      p.setRgba(
        (p.r * 0.88).round(),
        (p.g * 0.88).round(),
        (p.b * 0.88).round(),
        p.a,
      );
    }
  }
  File('assets/images/wisp_icon_round_dark.png')
      .writeAsBytesSync(img.encodePng(dark));

  // ---- 3) Adaptive-Icon-Foreground (Safe-Zone ~66 %) --------------------
  const fgSize = 1024;
  final fgContent = (fgSize * 0.66).round();
  final fgScaled = img.copyResize(
    square,
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

  // ---- 4) Native Splash (day + night) -----------------------------------
  final splashDay = img.copyResize(
    round,
    width: 670,
    height: 670,
    interpolation: img.Interpolation.cubic,
  );
  final splashBytes = img.encodePng(splashDay);

  // Night: gleiche Dark-Variante wie oben (Hintergrund leicht dunkler).
  final splashNightSrc = img.Image.from(round);
  for (final p in splashNightSrc) {
    if (p.a == 0) continue;
    final isNearWhite = p.r > 235 && p.g > 235 && p.b > 235;
    if (!isNearWhite) {
      p.setRgba(
        (p.r * 0.82).round(),
        (p.g * 0.82).round(),
        (p.b * 0.82).round(),
        p.a,
      );
    }
  }
  final splashNight = img.copyResize(
    splashNightSrc,
    width: 670,
    height: 670,
    interpolation: img.Interpolation.cubic,
  );
  final splashNightBytes = img.encodePng(splashNight);

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

  stdout.writeln('Logos erzeugt: round ${round.width}px, '
      'foreground ${fgSize}px, '
      '${dayDirs.length + nightDirs.length} Splash-Dateien');
}

double _dist(double dx, double dy) {
  final v = dx * dx + dy * dy;
  return v <= 0 ? 0 : _sqrt(v);
}

double _sqrt(double v) {
  // Newton-Verfahren (vermeidet dart:math Import-Duplikat).
  if (v == 0) return 0;
  var x = v;
  for (var i = 0; i < 24; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}
