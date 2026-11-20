import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Spotify-style animated equalizer bars, shown next to whatever collection or
/// track is currently playing.
///
/// The bars dance while [playing] is true *and* the app window is focused. When
/// paused they settle to a short, static baseline; when the window loses focus
/// the animation is stopped entirely so a backgrounded window doesn't keep a
/// repaint loop alive off-screen (per the "stop when out of focus" request).
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
  // Whether this instance holds the shared [_BarClock].
  bool _dancing = false;
  bool _tickersEnabled = true;

  // 1 while dancing, 0 while settled. Cross-fading between the two shapes
  // stops the bars jumping when playback is paused or resumed.
  late final AnimationController _blend;

  // Per-bar phase offsets and cycle counts give each bar its own rhythm so
  // they don't move in lockstep. Seeded once so they stay stable across
  // rebuilds.
  late final List<double> _phases;
  late final List<double> _cycles;

  bool _focused = true;

  static const Duration _blendDuration = Duration(milliseconds: 260);

  @override
  void initState() {
    super.initState();
    final rnd = Random(widget.barCount * 7 + 13);
    _phases = List<double>.generate(widget.barCount, (_) => rnd.nextDouble());
    // Whole sine cycles per clock period. A fractional count would leave
    // each bar part-way through its wave when the clock wraps back to 0,
    // jumping every bar to a new height once a period. Three to six cycles
    // across four seconds keeps the per-bar rhythm at 0.75-1.5 Hz.
    _cycles = List<double>.generate(
      widget.barCount,
      (_) => (3 + rnd.nextInt(4)).toDouble(),
    );
    WidgetsBinding.instance.addObserver(this);
    // lifecycleState is null until the first lifecycle event; treat that as
    // focused so the bars animate immediately on a freshly-launched window.
    final state = WidgetsBinding.instance.lifecycleState;
    _focused = state == null || state == AppLifecycleState.resumed;
    _blend = AnimationController(
      vsync: this,
      duration: _blendDuration,
      value: _shouldDance ? 1 : 0,
    );
    _syncAnimation();
  }

  bool get _shouldDance => widget.playing && _focused && _tickersEnabled;

  // The clock is a timer, which a muted subtree (minimised window) can't stop
  // on its own.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled == _tickersEnabled) return;
    _tickersEnabled = enabled;
    _syncAnimation(fade: enabled);
  }

  @override
  void didUpdateWidget(PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _syncAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final focused = state == AppLifecycleState.resumed;
    if (focused != _focused) {
      _focused = focused;
      // Nobody can see a fade in an unfocused window, and leaving one running
      // would keep a repaint loop alive off-screen.
      _syncAnimation(fade: focused);
    }
  }

  void _syncAnimation({bool fade = true}) {
    if (_shouldDance) {
      if (!_dancing) _BarClock.instance.acquire();
      _dancing = true;
      if (fade) {
        _blend.forward();
      } else {
        _blend.value = 1;
      }
      return;
    }

    // The wave freezes where it stopped and the settled shape grows out of
    // that exact frame, so the hand-off has no seam in either direction.
    if (_dancing) _BarClock.instance.release();
    _dancing = false;
    if (fade) {
      _blend.reverse();
    } else {
      _blend.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_dancing) _BarClock.instance.release();
    _blend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BarsPainter(
            animation: _BarClock.instance,
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

  final ValueListenable<double> animation;
  final Animation<double> blend;
  final List<double> phases;
  final List<double> cycles;
  final Color color;

  // Bars never fully collapse; settled (paused) bars rest above this minimum.
  static const double _minFactor = 0.28;

  @override
  void paint(Canvas canvas, Size size) {
    final n = phases.length;
    if (n == 0) return;

    final barWidth = size.width * 0.62 / n;
    final gap = (size.width - barWidth * n) / (n + 1);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final t = animation.value; // 0..1
    for (var i = 0; i < n; i++) {
      final wave = 0.5 + 0.5 * sin((t * cycles[i] + phases[i]) * 2 * pi);
      final settled = 0.18 * (1 + (i % 2));
      // Cross-faded between the two and mapped to [_minFactor, 1.0].
      final level = settled + (wave - settled) * blend.value;
      final factor = _minFactor + (1 - _minFactor) * level;

      final barHeight = size.height * factor;
      final left = gap + i * (barWidth + gap);
      final rect = Rect.fromLTWH(
        left,
        size.height - barHeight,
        barWidth,
        barHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.color != color || old.animation != animation || old.blend != blend;
}

/// The dancing bars' shared clock, cycling 0–1 every four seconds: one 10 fps
/// timer however many bars are on screen, rather than a vsync ticker each.
/// Every redraw repaints the whole window on Windows, and bars this small
/// read the same at 10 fps.
class _BarClock extends ValueNotifier<double> {
  _BarClock() : super(0);

  static final instance = _BarClock();

  static const _periodMicros = 4000000;

  final _watch = Stopwatch();
  Timer? _timer;
  int _holders = 0;

  void acquire() {
    if (_holders++ > 0) return;
    _watch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      value = _watch.elapsedMicroseconds % _periodMicros / _periodMicros;
    });
  }

  void release() {
    if (--_holders > 0) return;
    _timer?.cancel();
    _timer = null;
    _watch.stop();
  }
}
