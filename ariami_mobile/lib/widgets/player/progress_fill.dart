import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/playback_manager.dart';
import '../../utils/constants.dart';

/// How far the current song has played, painted as a block of [fill] from
/// the left in its own layer — the mini player's ground and the playing row
/// in a track list, as on Premium Desktop.
///
/// The player reports its position about five times a second, unevenly and
/// sometimes a hair behind its last report. Between reports the position is
/// carried forward on a clock, and the fill is redrawn exactly when its edge
/// reaches the next device pixel, never more than [_maxRate] times a second.
/// Small backward corrections are held; seeks and track changes jump at once.
/// Nothing is scheduled while paused.
class ProgressFill extends StatefulWidget {
  const ProgressFill({super.key, required this.fill, this.edge});

  final Color fill;

  /// When set, a thin playhead line in this colour at the fill's edge.
  final Color? edge;

  static const _maxRate = 30;

  /// One beat shared by every fill, so the mini player and the playing row
  /// redraw in the same frames.
  static final _beat = Stopwatch()..start();
  static const _beatMs = 1000 ~/ _maxRate;

  /// A change bigger than this is a seek or a new track, not jitter.
  static const _jumpMs = 750.0;

  @override
  State<ProgressFill> createState() => _ProgressFillState();
}

class _ProgressFillState extends State<ProgressFill> {
  final _playback = PlaybackManager();
  final _clock = Stopwatch();
  double _anchorMs = 0;
  double _shownMs = 0;
  double _devicePx = 0;
  Timer? _next;

  double get _totalMs =>
      (_playback.duration ?? Duration.zero).inMilliseconds.toDouble();

  int _pixel(double ms) =>
      _totalMs <= 0 ? 0 : (ms / _totalMs * _devicePx).floor();

  @override
  void initState() {
    super.initState();
    _playback.positionNotifier.addListener(_report);
    _playback.addListener(_report);
    _report();
  }

  @override
  void dispose() {
    _next?.cancel();
    _playback.positionNotifier.removeListener(_report);
    _playback.removeListener(_report);
    super.dispose();
  }

  /// A new position report, or a play/pause/track change.
  void _report() {
    _anchorMs = _playback.position.inMilliseconds.toDouble();
    _clock
      ..reset()
      ..start();
    _advance();
  }

  double get _estimateMs => math.min(
        _anchorMs + (_playback.isPlaying ? _clock.elapsedMilliseconds : 0),
        _totalMs,
      );

  void _advance() {
    _next?.cancel();
    _next = null;
    if (!mounted) return;
    final estimate = _estimateMs;
    final behind = _shownMs - estimate;
    final shown =
        behind > 0 && behind < ProgressFill._jumpMs ? _shownMs : estimate;
    if (_pixel(shown) != _pixel(_shownMs) || shown < _shownMs) {
      setState(() => _shownMs = shown);
    } else {
      _shownMs = shown;
    }

    if (!_playback.isPlaying || _totalMs <= 0 || _devicePx <= 0) return;
    final msPerPixel = _totalMs / _devicePx;
    final due = (_pixel(_shownMs) + 1) * msPerPixel - estimate;
    final now = ProgressFill._beat.elapsedMilliseconds;
    final at = now + due.clamp(ProgressFill._beatMs.toDouble(), 1000.0);
    final onBeat = (at / ProgressFill._beatMs).ceil() * ProgressFill._beatMs;
    _next = Timer(Duration(milliseconds: onBeat - now), _advance);
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePx = constraints.maxWidth * dpr;
        if (devicePx != _devicePx) {
          _devicePx = devicePx;
          WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
        }
        final total = _totalMs;
        return RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _FillPainter(
              fraction: total <= 0 ? 0 : (_shownMs / total).clamp(0.0, 1.0),
              fill: widget.fill,
              edge: widget.edge,
            ),
          ),
        );
      },
    );
  }
}

/// A track row that fills with the playing song's progress while [songId]
/// is the current song, as the playing row does on Premium Desktop.
class ProgressFillRow extends StatelessWidget {
  const ProgressFillRow({
    super.key,
    required this.songId,
    required this.child,
    this.enabled = true,
  });

  final String songId;
  final Widget child;

  /// Off for rows that show the song but are not the playing entry, such as
  /// a later copy of it in the queue.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackManager();
    return ListenableBuilder(
      listenable: playback,
      child: child,
      builder: (context, child) => Stack(
        children: [
          // Always present so the row itself is never remounted.
          Positioned.fill(
            child: enabled && playback.currentSong?.id == songId
                ? ProgressFill(fill: context.colors.fill)
                : const SizedBox.shrink(),
          ),
          child!,
        ],
      ),
    );
  }
}

class _FillPainter extends CustomPainter {
  _FillPainter({required this.fraction, required this.fill, this.edge});

  final double fraction;
  final Color fill;
  final Color? edge;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * fraction;
    canvas.drawRect(Rect.fromLTWH(0, 0, x, size.height), Paint()..color = fill);
    final edge = this.edge;
    if (edge != null && x > 0) {
      canvas.drawRect(
          Rect.fromLTWH(x - 1, 0, 2, size.height), Paint()..color = edge);
    }
  }

  @override
  bool shouldRepaint(_FillPainter old) =>
      old.fraction != fraction || old.fill != fill || old.edge != edge;
}
