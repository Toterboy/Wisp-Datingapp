import 'package:flutter/material.dart';

/// App-Logo für WispDating — das neue runde Logo
/// (`wispdating_logo_round.png`). Der farbige Verlauf funktioniert in
/// Light- UND Dark-Mode, eine separate Dark-Variante ist nicht nötig.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheDim = (size * pixelRatio).toInt();
    return RepaintBoundary(
      child: ClipOval(
        child: Image.asset(
          'assets/images/wispdating_logo_round.png',
          width: size,
          height: size,
          cacheWidth: cacheDim,
          cacheHeight: cacheDim,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
