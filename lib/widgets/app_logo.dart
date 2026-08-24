import 'package:flutter/material.dart';

/// App-Logo für WispDating — rund, ohne Ecken und ohne Hintergrund.
///
/// Nutzt `wisp_icon_round.png` (Light) bzw. `wisp_icon_round_dark.png`
/// (Dark: weiße Design-Flächen sind auf dunkles Grau gemappt, damit im
/// Dark Mode keine leuchtenden Stellen übrig bleiben). Ein [ClipOval]
/// schneidet alles außerhalb des Kreises ab, unabhängig vom Asset-Inhalt.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isDark
        ? 'assets/images/wisp_icon_round_dark.png'
        : 'assets/images/wisp_icon_round.png';
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheDim = (size * pixelRatio).toInt();
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        color: Colors.transparent,
        child: ClipOval(
          child: Image.asset(
            asset,
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
