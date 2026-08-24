import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vollbild-„Funke"-Animation: leuchtendes Herz + Partikel-Explosion,
/// kurz eingeblendet, wenn ein Funke entsteht (Match).
///
/// Nutzung: `await FunkeOverlay.show(context);`
class FunkeOverlay extends StatefulWidget {
  const FunkeOverlay({super.key});

  /// Zeigt die Animation ~1,8 s und schließt sie dann von selbst.
  static Future<void> show(BuildContext context) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => const FunkeOverlay(),
    ).then((_) {});
  }

  @override
  State<FunkeOverlay> createState() => _FunkeOverlayState();
}

class _FunkeOverlayState extends State<FunkeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;
  final math.Random _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Partikel auf einem Ring um das Zentrum verteilen.
    _particles = List.generate(26, (i) {
      final angle = (i / 26) * 2 * math.pi + _rnd.nextDouble() * 0.4;
      final speed = 0.55 + _rnd.nextDouble() * 0.65;
      final size = 3.0 + _rnd.nextDouble() * 5.0;
      final color = Color.lerp(
        const Color(0xFFFF6B9D),
        const Color(0xFFFFC46B),
        _rnd.nextDouble(),
      )!;
      return _Particle(angle: angle, speed: speed, size: size, color: color);
    });

    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          // Herz: 0-0.35 einblenden+skalieren (overshoot), 0.8-1.0 ausblenden.
          final heartScale = t < 0.35
              ? Curves.elasticOut.transform(t / 0.35)
              : (t > 0.85
                  ? 1.0 - Curves.easeIn.transform((t - 0.85) / 0.15)
                  : 1.0);
          final heartOpacity = t > 0.85
              ? 1.0 - (t - 0.85) / 0.15
              : (t < 0.08 ? t / 0.08 : 1.0);
          // Partikel fliegen ab 0.25 nach außen und faden aus.
          final particleT = ((t - 0.25) / 0.75).clamp(0.0, 1.0);

          return Center(
            child: SizedBox(
              width: 320,
              height: 320,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (final p in _particles)
                    Positioned(
                      left: 160 +
                          math.cos(p.angle) * p.speed * 140 * particleT -
                          p.size / 2,
                      top: 160 +
                          math.sin(p.angle) * p.speed * 140 * particleT -
                          p.size / 2,
                      child: Opacity(
                        opacity: (1 - particleT).clamp(0.0, 1.0),
                        child: Container(
                          width: p.size,
                          height: p.size,
                          decoration: BoxDecoration(
                            color: p.color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: p.color.withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Transform.scale(
                    scale: 0.4 + heartScale * 0.6,
                    child: Opacity(
                      opacity: heartOpacity.clamp(0.0, 1.0),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            size: 96,
                            color: Color(0xFFFF6B9D),
                            shadows: [
                              Shadow(
                                color: Color(0x88FF6B9D),
                                blurRadius: 32,
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Ein Funke ist entstanden!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(color: Colors.black45, blurRadius: 8),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
  });

  final double angle;
  final double speed;
  final double size;
  final Color color;
}
