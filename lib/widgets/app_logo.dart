import 'package:flutter/material.dart';

/// App-Logo für Wisp – rund, ohne Ecken und ohne Hintergrund.
///
/// Nutzt `wisp_icon_round.png`. Das Asset hat KEINE transparenten Ecken,
/// sondern einen opaken schwarzen Hintergrund (im Dark Mode unsichtbar,
/// im Light Mode als schwarzes Rechteck sichtbar) – deshalb schneidet ein
/// [ClipOval] alles außerhalb des Kreises ab. So bleibt das Logo in Light-
/// UND Dark Mode sauber rund, unabhängig vom Asset-Inhalt.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheDim = (size * pixelRatio).toInt();
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        color: Colors.transparent,
        child: ClipOval(
          child: Image.asset(
            'assets/images/wisp_icon_round.png',
            width: size,
            height: size,
            cacheWidth: cacheDim,
            cacheHeight: cacheDim,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
