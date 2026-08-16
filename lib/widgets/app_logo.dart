import 'package:flutter/material.dart';

/// App-Logo für Wisp – rund, ohne Ecken und ohne Hintergrund.
///
/// Nutzt `wisp_icon_round.png` (Badge in einen Kreis maskiert, Ecken
/// transparent) und funktioniert dadurch identisch in Light- und Dark Mode.
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
        child: Image.asset(
          'assets/images/wisp_icon_round.png',
          width: size,
          height: size,
          cacheWidth: cacheDim,
          cacheHeight: cacheDim,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
