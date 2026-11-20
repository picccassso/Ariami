import 'dart:async';
import 'dart:math' as math;

import 'package:ariami_core/utils/format.dart';
import 'package:flutter/material.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../theme/player_theme.dart';

/// A [ProgressFillPainter] in its own layer that glides one device pixel at
/// a time.
///
/// The player reports its position about five times a second, at slightly
/// uneven intervals and sometimes a hair behind its last report. Drawing
/// those reports directly makes a wide bar step a pixel or two at a time,
/// unevenly. Instead, between reports the position is carried forward on a
/// clock, and the fill is redrawn exactly when its edge reaches the next
/// device pixel — no sooner, so a narrow row redraws rarely, and never more
/// than [_maxRate] times a second. Small backward corrections are held
/// rather than shown; real seeks and track changes jump at once. While the
/// source loads, the fill holds at the last report rather than gliding ahead.
///
/// It sits behind a [RepaintBoundary], so each redraw re-rasterises only
/// this strip, never the window around it. Nothing is scheduled while
/// paused or loading.
class ProgressFill extends StatefulWidget {
  const ProgressFill({
    super.key,
    required this.audio,
    required this.fill,
    required this.ink,
    this.drag,
    this.hover,
    this.hoverBand,
    this.ground = Colors.black,
    this.edge = true,
  });

  final AudioController audio;
  final Color fill;
  final Color ink;
  final double? drag;
  final double? hover;
  final double? hoverBand;
  final Color ground;
  final bool edge;

  /// The most redraws a second a fill will ask for.
  static const _maxRate = 30;

  /// One beat shared by every fill: wake-ups snap to it, so the bar, the
  /// playing row and the queue row redraw in the same frames rather than
  /// each adding frames of their own.
  static final _beat = Stopwatch()..start();
  static const _beatMs = 1000 ~/ _maxRate;

  /// A position change bigger than this is a seek or a new track, not
  /// reporting jitter, and is shown at once even when it goes backwards.
  static const _jumpMs = 750.0;

  @override
  State<ProgressFill> createState() => _ProgressFillState();
}

class _ProgressFillState extends State<ProgressFill> {
  /// Time since [_anchorMs] was reported.
  final _clock = Stopwatch();
  double _anchorMs = 0;

  /// Track the last report was for, so a track change jumps even mid-load.
  Track? _lastTrack;

  /// The position drawn, in milliseconds.
  double _shownMs = 0;

  /// The fill's width in device pixels, from the last layout.
  double _devicePx = 0;

  Timer? _next;

  AudioController get _audio => widget.audio;

  double get _totalMs =>
      (_audio.duration ?? Duration.zero).inMilliseconds.toDouble();

  int _pixel(double ms) =>
      _totalMs <= 0 ? 0 : (ms / _totalMs * _devicePx).floor();

  @override
  void initState() {
    super.initState();
    _audio.addTickingListener(_report);
    _report();
  }

  @override
  void didUpdateWidget(ProgressFill old) {
    super.didUpdateWidget(old);
    if (identical(old.audio, widget.audio)) return;
    old.audio.removeTickingListener(_report);
    widget.audio.addTickingListener(_report);
    _report();
  }

  @override
  void dispose() {
    _next?.cancel();
    _audio.removeTickingListener(_report);
    super.dispose();
  }

  /// A new position report, or a play/pause/track change.
  void _report() {
    final track = _audio.currentTrack;
    final trackChanged = !identical(track, _lastTrack);
    _lastTrack = track;
    _anchorMs = _audio.position.inMilliseconds.toDouble();
    _clock
      ..reset()
      ..start();
    // A track change always jumps at once, even mid-load.
    if (trackChanged) _shownMs = _anchorMs;
    _advance();
  }

  /// Where the song is now: the last report carried forward while playing —
  /// unless the source is still loading, where the fill holds at the report.
  double get _estimateMs => math.min(
        _anchorMs +
            (_audio.isPlaying && !_audio.isLoading
                ? _clock.elapsedMilliseconds
                : 0),
        _totalMs,
      );

  void _advance() {
    _next?.cancel();
    _next = null;
    if (!mounted) return;
    final estimate = _estimateMs;
    // Reporting jitter can put a report a little behind what is already
    // drawn; hold until the clock catches up rather than step backwards.
    // While loading, every backward report is pre-seek jitter — hold it too.
    final behind = _shownMs - estimate;
    final shown = behind > 0 &&
            (_audio.isLoading || behind < ProgressFill._jumpMs)
        ? _shownMs
        : estimate;
    if (_pixel(shown) != _pixel(_shownMs) || shown < _shownMs) {
      setState(() => _shownMs = shown);
    } else {
      _shownMs = shown;
    }

    if (!_audio.isPlaying ||
        _audio.isLoading ||
        _totalMs <= 0 ||
        _devicePx <= 0) {
      return;
    }
    // Wake when the edge reaches the next device pixel.
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
          // Re-time the next wake-up for the new width.
          WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
        }
        final total = _totalMs;
        return RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: ProgressFillPainter(
              audio: _audio,
              fraction: total <= 0 ? 0 : (_shownMs / total).clamp(0.0, 1.0),
              fill: widget.fill,
              ink: widget.ink,
              drag: widget.drag,
              hover: widget.hover,
              hoverBand: widget.hoverBand,
              ground: widget.ground,
              edge: widget.edge,
            ),
          ),
        );
      },
    );
  }
}

/// Paints how far the current song has played as a block of [fill] from the
/// left — the transport bar's ground and the playing row's in a track list.
/// Use it through [ProgressFill], which decides when it repaints.
///
/// Without a [hoverBand] the playhead is an [ink] edge down the full height.
/// With one, the fill stays plain colour and the playhead lives on a seek bar
/// along the top edge instead, so nothing that looks draggable crosses the
/// controls below it.
class ProgressFillPainter extends CustomPainter {
  ProgressFillPainter({
    required this.audio,
    required this.fraction,
    required this.fill,
    required this.ink,
    this.drag,
    this.hover,
    this.hoverBand,
    this.ground = Colors.black,
    this.edge = true,
  });

  /// For the hover label's time.
  final AudioController audio;

  /// How far the song has played, as a fraction.
  final double fraction;
  final Color fill;
  final Color ink;

  /// A scrub in progress, as a fraction; drawn in place of the playhead.
  final double? drag;

  /// The pointer's position as a fraction, marked with a faint line.
  final double? hover;

  /// When seeking is confined to a strip this tall along the top edge, a
  /// seek bar is drawn there: thin at rest, thicker with a handle and the
  /// time under the pointer while hovered or dragged.
  final double? hoverBand;

  /// The hover time label's text colour.
  final Color ground;

  /// Whether to draw the ink edge at the playhead.
  final bool edge;

  @override
  void paint(Canvas canvas, Size size) {
    final totalMs = (audio.duration ?? Duration.zero).inMilliseconds;
    if (totalMs <= 0) return;
    final x = size.width * (drag ?? fraction);
    canvas.drawRect(Rect.fromLTWH(0, 0, x, size.height), Paint()..color = fill);
    final hover = this.hover;

    if (hoverBand == null) {
      if (edge) {
        canvas.drawRect(
          Rect.fromLTWH(x - 1, 0, 2, size.height),
          Paint()..color = ink.withValues(alpha: 0.85),
        );
      }
      if (hover != null && drag == null) {
        canvas.drawRect(
          Rect.fromLTWH(size.width * hover, 0, 1, size.height),
          Paint()..color = ink.withValues(alpha: 0.3),
        );
      }
      return;
    }

    // The seek bar along the top edge.
    final active = hover != null || drag != null;
    final h = active ? 5.0 : 3.0;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, h),
      Paint()..color = ink.withValues(alpha: 0.16),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, x, h),
      Paint()..color = ink.withValues(alpha: 0.9),
    );
    if (!active) return;
    canvas.drawCircle(Offset(x, h / 2 + 1), 6, Paint()..color = ink);

    // Where a click would land, and when that is.
    final at = drag ?? hover!;
    final atX = size.width * at;
    if (drag == null) {
      canvas.drawRect(
        Rect.fromLTWH(atX - 1, 0, 2, h),
        Paint()..color = ink.withValues(alpha: 0.6),
      );
    }
    final label = TextPainter(
      text: TextSpan(
        text:
            formatClockDuration(Duration(milliseconds: (totalMs * at).round())),
        style: TextStyle(
          fontFamily: PlayerTheme.bodyFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ground,
          fontFeatures: PlayerTheme.tabular,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pill = Size(label.width + 12, label.height + 4);
    final left = (atX - pill.width / 2).clamp(4.0, size.width - pill.width - 4);
    // Above the bar, clear of the controls beneath it; the bar's stacks
    // don't clip, so this paints over the content above.
    final box = Rect.fromLTWH(left, -pill.height - 8, pill.width, pill.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          box, const Radius.circular(PlayerTheme.cardRadius)),
      Paint()..color = ink,
    );
    label.paint(canvas, box.topLeft + const Offset(6, 2));
  }

  @override
  bool shouldRepaint(ProgressFillPainter old) =>
      old.fraction != fraction ||
      old.drag != drag ||
      old.hover != hover ||
      old.hoverBand != hoverBand ||
      old.ground != ground ||
      old.fill != fill ||
      old.ink != ink ||
      old.edge != edge ||
      !identical(old.audio, audio);
}
