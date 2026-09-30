import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Paints the still ambient glow (three soft light pools on the dark base)
/// behind [child], whose Scaffold must then be transparent.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: RepaintBoundary(child: CustomPaint(painter: _GlowPainter())),
        ),
        child,
      ],
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter();

  static const _centers = [
    Alignment(-0.65, -0.8),
    Alignment(0.75, -0.35),
    Alignment(0, 0.9),
  ];
  static const _radii = [0.6, 0.5, 0.48];
  static const _strength = [0.7, 0.55, 0.5];

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = AppColors.base);
    for (var i = 0; i < 3; i++) {
      final color = AppColors.glows[i];
      final alpha = _strength[i];
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.4),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(
            center: _centers[i].withinRect(bounds),
            radius: size.longestSide * _radii[i],
          )),
      );
    }
    // Settle the lower edge back toward the base so content there sits on
    // calm ground.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.base.withValues(alpha: 0),
            AppColors.base.withValues(alpha: 0.55),
          ],
          stops: const [0.55, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => false;
}
