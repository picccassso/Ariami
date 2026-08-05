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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final List<double> _phases;
  late final List<double> _speeds;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final random = Random(widget.barCount * 7 + 13);
    _phases = List.generate(widget.barCount, (_) => random.nextDouble());
    _speeds = List.generate(
      widget.barCount,
      (_) => 0.7 + random.nextDouble(),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _syncAnimation();
  }

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
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.playing && _foreground) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
            phases: _phases,
            speeds: _speeds,
            color: widget.color,
            animating: widget.playing && _foreground,
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.animation,
    required this.phases,
    required this.speeds,
    required this.color,
    required this.animating,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<double> phases;
  final List<double> speeds;
  final Color color;
  final bool animating;

  static const _minimumHeight = 0.28;

  @override
  void paint(Canvas canvas, Size size) {
    if (phases.isEmpty) return;

    final barWidth = size.width * 0.62 / phases.length;
    final gap = (size.width - barWidth * phases.length) / (phases.length + 1);
    final paint = Paint()..color = color;

    for (var i = 0; i < phases.length; i++) {
      final factor = animating
          ? _minimumHeight +
              (1 - _minimumHeight) *
                  (0.5 +
                      0.5 *
                          sin((animation.value * speeds[i] + phases[i]) *
                              2 *
                              pi))
          : _minimumHeight + (1 - _minimumHeight) * 0.18 * (1 + (i % 2));
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
      oldDelegate.animating != animating ||
      oldDelegate.animation != animation;
}
