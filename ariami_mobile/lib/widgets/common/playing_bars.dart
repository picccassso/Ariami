import 'dart:math';

import 'package:flutter/material.dart';

/// Animated equalizer bars for the album or playlist that owns the queue.
///
/// They dance while [playing] and the app is in the foreground, then settle
/// into a static equalizer profile while playback is paused.
class PlayingBars extends StatefulWidget {
  const PlayingBars({
    super.key,
    required this.playing,
    required this.color,
    this.size = 16,
    this.barCount = 4,
  });

  final bool playing;
  final Color color;
  final double size;
  final int barCount;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  // 1 while dancing, 0 while settled. Cross-fading between the two shapes
  // stops the bars jumping when playback is paused or resumed.
  late final AnimationController _blend;
  late final List<double> _phases;
  late final List<double> _cycles;
  bool _foreground = true;

  static const Duration _blendDuration = Duration(milliseconds: 260);

  @override
  void initState() {
    super.initState();
    final random = Random(widget.barCount * 7 + 13);
    _phases = List.generate(widget.barCount, (_) => random.nextDouble());
    // Whole sine cycles per controller period. A fractional count would leave
    // each bar part-way through its wave when the controller wraps back to 0,
    // jumping every bar to a new height once a period. Three to six cycles
    // across four seconds keeps the per-bar rhythm at 0.75-1.5 Hz.
    _cycles = List.generate(
      widget.barCount,
      (_) => (3 + random.nextInt(4)).toDouble(),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _blend = AnimationController(
      vsync: this,
      duration: _blendDuration,
      value: _shouldDance ? 1 : 0,
    );
    _syncAnimation();
  }

  bool get _shouldDance => widget.playing && _foreground;

  @override
  void didUpdateWidget(PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _syncAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    // Nobody can see a fade the app is no longer showing, and leaving one
    // running would keep a repaint loop alive off-screen.
    _syncAnimation(fade: foreground);
  }

  void _syncAnimation({bool fade = true}) {
    if (_shouldDance) {
      if (!_controller.isAnimating) _controller.repeat();
      if (fade) {
        _blend.forward();
      } else {
        _blend.value = 1;
      }
      return;
    }

    // The wave freezes where it stopped and the settled shape grows out of
    // that exact frame, so the hand-off has no seam in either direction.
    _controller.stop();
    if (fade) {
      _blend.reverse();
    } else {
      _blend.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _blend.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BarsPainter(
            animation: _controller,
            blend: _blend,
            phases: _phases,
            cycles: _cycles,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.animation,
    required this.blend,
    required this.phases,
    required this.cycles,
    required this.color,
  }) : super(repaint: Listenable.merge([animation, blend]));

  final Animation<double> animation;
  final Animation<double> blend;
  final List<double> phases;
  final List<double> cycles;
  final Color color;

  static const _minimumHeight = 0.28;

  @override
  void paint(Canvas canvas, Size size) {
    if (phases.isEmpty) return;

    final barWidth = size.width * 0.62 / phases.length;
    final gap = (size.width - barWidth * phases.length) / (phases.length + 1);
    final paint = Paint()..color = color;

    for (var i = 0; i < phases.length; i++) {
      final wave = 0.5 +
          0.5 * sin((animation.value * cycles[i] + phases[i]) * 2 * pi);
      // Settled: a gentle static profile so it still reads as an equalizer.
      final settled = 0.18 * (1 + (i % 2));
      final level = settled + (wave - settled) * blend.value;
      final factor = _minimumHeight + (1 - _minimumHeight) * level;
      final height = size.height * factor;
      final rect = Rect.fromLTWH(
        gap + i * (barWidth + gap),
        size.height - height,
        barWidth,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.animation != animation ||
      oldDelegate.blend != blend;
}
