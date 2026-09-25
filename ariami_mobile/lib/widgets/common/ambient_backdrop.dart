import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/audio/audio_level_meter.dart';
import '../../services/playback_manager.dart';
import '../../services/theme_service.dart';
import '../../utils/constants.dart';

/// The player's [AmbientBackdrop]: it drifts when the user has turned that
/// on and music is playing on this device (a cast or Connect session stays
/// still), and also pulses on each kick when [pulse] is set — only on the
/// full player, since a flash behind lists being read is a distraction.
class PlayerBackdrop extends StatelessWidget {
  const PlayerBackdrop({
    super.key,
    this.layoutSeed = 0,
    this.pulse = false,
    this.foreground,
  });

  final int layoutSeed;
  final bool pulse;
  final Widget? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeService();
    final playback = PlaybackManager();
    return ListenableBuilder(
      listenable: Listenable.merge([theme, playback]),
      child: foreground,
      builder: (context, foreground) => AmbientBackdrop(
        layoutSeed: layoutSeed,
        moving: theme.movingBackdrop && playback.isPlayingHere,
        levels: pulse ? AudioLevelMeter.instance : null,
        foreground: foreground,
      ),
    );
  }
}

/// The screen-wide backdrop behind the glass panels: the theme's base colour
/// lit by three soft glows ([PlayerColors.glowA]–[PlayerColors.glowC]).
///
/// The glow colours come from the theme, so they cross-fade with every theme
/// transition (e.g. a new cover-art palette). [layoutSeed] places the glows;
/// changing it (the shell passes the playing album) drifts them to a new
/// arrangement. While [moving] is set the glows also keep wandering around
/// that arrangement — pulsing on each kick when [levels] is given, with the
/// kick also flashing over any [foreground] (e.g. blurred artwork) that
/// would otherwise hide it; otherwise
/// nothing animates while the seed is unchanged, so an idle player costs no
/// frames.
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({
    super.key,
    this.layoutSeed = 0,
    this.moving = false,
    this.levels,
    this.foreground,
  });

  final int layoutSeed;
  final bool moving;
  final AudioLevelMeter? levels;
  final Widget? foreground;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _drift = ValueNotifier(_Drift.still);
  Duration _last = Duration.zero;
  AudioLevelMeter? _metering;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (widget.moving) _ticker.start();
    _syncMetering();
  }

  @override
  void didUpdateWidget(AmbientBackdrop old) {
    super.didUpdateWidget(old);
    if (widget.moving && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    _syncMetering();
  }

  // Holds the meter only while moving, so nothing is metered otherwise.
  void _syncMetering() {
    final wanted = widget.moving ? widget.levels : null;
    if (wanted == _metering) return;
    _metering?.release();
    _metering = wanted?..acquire();
  }

  // Eases the drift in and out rather than snapping, and stops the ticker
  // once it has fully settled back so a paused player costs no frames.
  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final d = _drift.value;
    final target = widget.moving ? 1.0 : 0.0;
    final amount = d.amount + (target - d.amount) * (1 - math.exp(-dt / 0.8));
    // Kicks snap the pulse on instantly, then it falls away quickly — the
    // "slap" — rather than swelling in and out.
    final pulse = math.max(
      d.pulse * math.exp(-dt / 0.16),
      _metering?.sample() ?? 0,
    );
    if (!widget.moving && amount < 0.001) {
      _ticker.stop();
      _drift.value = _Drift(d.time, 0, 0);
      return;
    }
    // Beats briefly speed the drift up, so the glows lurch with the music.
    _drift.value = _Drift(d.time + dt * (1 + 0.75 * pulse), amount, pulse);
  }

  @override
  void dispose() {
    _metering?.release();
    _ticker.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RepaintBoundary(
      child: TweenAnimationBuilder<_GlowLayout>(
        tween: _GlowLayoutTween(end: _GlowLayout.fromSeed(widget.layoutSeed)),
        duration: const Duration(milliseconds: 1800),
        curve: Curves.easeInOutCubic,
        child: widget.foreground,
        builder: (context, layout, foreground) {
          CustomPaint glows({required bool flash}) => CustomPaint(
                painter: _AmbientPainter(
                  colors: colors,
                  layout: layout,
                  drift: _drift,
                  flash: flash,
                ),
                size: Size.infinite,
              );
          if (foreground == null) return glows(flash: false);
          return Stack(
            fit: StackFit.expand,
            children: [
              glows(flash: false),
              RepaintBoundary(child: foreground),
              glows(flash: true),
            ],
          );
        },
      ),
    );
  }
}

/// How far into the drift cycle the glows are ([time], seconds), how much
/// of it is applied ([amount], 0–1) and the current beat [pulse] (0–1).
@immutable
class _Drift {
  const _Drift(this.time, this.amount, this.pulse);

  static const still = _Drift(0, 0, 0);

  final double time;
  final double amount;
  final double pulse;
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

  // Value equality: TweenAnimationBuilder restarts whenever the target
  // changes, so an equal-but-new layout on rebuild must not count.
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
  _AmbientPainter({
    required this.colors,
    required this.layout,
    required this.drift,
    required this.flash,
  }) : super(repaint: drift);

  final PlayerColors colors;
  final _GlowLayout layout;
  final ValueListenable<_Drift> drift;

  /// Paints only the kick's flash of the glows, over a foreground.
  final bool flash;

  static const _strength = [0.7, 0.55, 0.5];

  // Per-glow drift: angular speeds (rad/s) for x and y, and phase offsets.
  // Unrelated periods (roughly 11–29 s) keep the glows from moving in step
  // or visibly repeating.
  static const _speedX = [0.41, 0.29, 0.53];
  static const _speedY = [0.33, 0.47, 0.22];
  static const _phase = [0.0, 2.1, 4.2];
  static const _wander = 0.45; // alignment units
  static const _breathe = 0.18; // fraction of radius
  // Half the desktop's punch: up close on a phone, a softer beat reads as a
  // breath rather than a strobe.
  static const _pulseGrow = 0.15; // fraction of radius on a full kick
  static const _pulseGlow = 0.3; // fraction of strength on a full kick
  static const _flashGlow = 0.3; // flash strength over a foreground

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final d = drift.value;
    final beat = d.pulse * d.amount;
    if (flash && beat < 0.01) return;
    if (!flash) canvas.drawRect(bounds, Paint()..color = colors.base);

    final glows = [colors.glowA, colors.glowB, colors.glowC];
    for (var i = 0; i < 3; i++) {
      final t = d.time;
      final center = (layout.centers[i] +
              Alignment(
                    math.sin(t * _speedX[i] + _phase[i]),
                    math.cos(t * _speedY[i] + _phase[i]),
                  ) *
                  (_wander * d.amount))
          .withinRect(bounds);
      final radius = size.longestSide *
          layout.radii[i] *
          (1 +
              _breathe * d.amount * math.sin(t * _speedY[i] * 1.7 + _phase[i]) +
              _pulseGrow * beat);
      final color = glows[i];
      final alpha = flash
          ? _strength[i] * _flashGlow * beat
          : math.min(1.0, _strength[i] * (1 + _pulseGlow * beat));
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
    if (flash) return;

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
      old.colors != colors || old.layout != layout || old.flash != flash;
}
