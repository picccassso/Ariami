import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// The screen-wide backdrop behind the glass panels: the theme's base colour
/// lit by three soft glows ([PlayerColors.glowA]–[PlayerColors.glowC]).
///
/// The glow colours come from the theme, so they cross-fade with every theme
/// transition (e.g. a new cover-art palette). [layoutSeed] places the glows;
/// changing it (passing the playing album) drifts them to a new arrangement.
/// Nothing animates while the seed is unchanged, so an idle player costs no frames.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key, this.layoutSeed = 0});

  final int layoutSeed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RepaintBoundary(
      child: TweenAnimationBuilder<_GlowLayout>(
        tween: _GlowLayoutTween(end: _GlowLayout.fromSeed(layoutSeed)),
        duration: const Duration(milliseconds: 1800),
        curve: Curves.easeInOutCubic,
        builder: (context, layout, _) => CustomPaint(
          painter: _AmbientPainter(colors: colors, layout: layout),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Glow centres (as [Alignment]s) and radii (fractions of the longest side).
@immutable
class _GlowLayout {
  const _GlowLayout(this.centers, this.radii);

  factory _GlowLayout.fromSeed(int seed) {
    final r = math.Random(seed);
    double between(double a, double b) => a + r.nextDouble() * (b - a);
    return _GlowLayout(
      [
        // One glow per region so they never pile up in the same corner.
        Alignment(between(-1.0, -0.3), between(-1.1, -0.5)),
        Alignment(between(0.4, 1.1), between(-0.8, 0.1)),
        Alignment(between(-0.5, 0.5), between(0.6, 1.2)),
      ],
      [between(0.5, 0.68), between(0.42, 0.6), between(0.4, 0.55)],
    );
  }

  final List<Alignment> centers;
  final List<double> radii;

  @override
  bool operator ==(Object other) =>
      other is _GlowLayout &&
      listEquals(other.centers, centers) &&
      listEquals(other.radii, radii);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(centers), Object.hashAll(radii));
}

class _GlowLayoutTween extends Tween<_GlowLayout> {
  _GlowLayoutTween({super.end});

  @override
  _GlowLayout lerp(double t) {
    final a = begin ?? end!;
    final b = end!;
    return _GlowLayout(
      [
        for (var i = 0; i < 3; i++)
          Alignment.lerp(a.centers[i], b.centers[i], t)!,
      ],
      [for (var i = 0; i < 3; i++) a.radii[i] + (b.radii[i] - a.radii[i]) * t],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({required this.colors, required this.layout});

  final PlayerColors colors;
  final _GlowLayout layout;

  static const _strength = [0.7, 0.55, 0.5];

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = colors.base);

    final glows = [colors.glowA, colors.glowB, colors.glowC];
    for (var i = 0; i < 3; i++) {
      final center = layout.centers[i].withinRect(bounds);
      final radius = size.longestSide * layout.radii[i];
      final color = glows[i];
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
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Settle the lower edge back toward the base so bottom controls always
    // sit on calm ground, whatever the glows are doing.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.base.withValues(alpha: 0),
            colors.base.withValues(alpha: 0.55),
          ],
          stops: const [0.55, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.colors != colors || old.layout != layout;
}
