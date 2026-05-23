import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Displays single-line text that scrolls horizontally when it overflows.
///
/// Uses Spotify-style continuous looping: two copies of the text are rendered
/// with a gap between them, and the animation scrolls seamlessly in an infinite
/// loop. When the first copy scrolls off-screen, the position resets to show
/// the second copy (now in the starting position), creating a seamless effect.
///
/// The widget is intentionally resilient to frequent parent rebuilds: the
/// measured text width and the container width are cached in state, so a
/// rebuild driven by something unrelated (e.g. a playback position tick)
/// does not reset the scroll animation.
class AdaptiveMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double height;
  final double velocity;
  final Duration startPause;

  /// Gap between the two text copies in the continuous loop.
  final double gapWidth;

  const AdaptiveMarqueeText({
    super.key,
    required this.text,
    this.style,
    required this.height,
    this.velocity = 30.0,
    this.startPause = const Duration(milliseconds: 1500),
    this.gapWidth = 48.0,
  });

  static TextPainter createTextPainter({
    required String text,
    required TextStyle? style,
    required TextScaler textScaler,
  }) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
  }

  static double measureTextWidth({
    required String text,
    required TextStyle? style,
    required TextScaler textScaler,
  }) {
    return createTextPainter(
      text: text,
      style: style,
      textScaler: textScaler,
    ).width;
  }

  static bool textOverflows({
    required String text,
    required TextStyle? style,
    required TextScaler textScaler,
    required double maxWidth,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return false;
    }
    return measureTextWidth(
          text: text,
          style: style,
          textScaler: textScaler,
        ) >
        maxWidth;
  }

  @override
  State<AdaptiveMarqueeText> createState() => _AdaptiveMarqueeTextState();
}

class _AdaptiveMarqueeTextState extends State<AdaptiveMarqueeText>
    with SingleTickerProviderStateMixin {
  static const double _widthEpsilon = 0.5;

  /// Buffer added to measured text width to prevent clipping from font
  /// rendering differences between TextPainter measurement and Text widget.
  static const double _textWidthBuffer = 12.0;

  late final AnimationController _controller;
  double? _cachedTextWidth;
  TextScaler? _cachedTextScaler;
  double? _containerWidth;
  int _generation = 0;
  bool _reconfigureScheduled = false;
  bool _initialPauseComplete = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(AdaptiveMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);

    final contentChanged =
        oldWidget.text != widget.text || oldWidget.style != widget.style;

    if (contentChanged) {
      _cachedTextWidth = null;
      _cachedTextScaler = null;
      _initialPauseComplete = false;
    }

    if (contentChanged ||
        oldWidget.velocity != widget.velocity ||
        oldWidget.startPause != widget.startPause ||
        oldWidget.gapWidth != widget.gapWidth) {
      _scheduleReconfigure();
    }
  }

  /// For continuous loop: scroll distance = textWidth + gapWidth
  /// This scrolls until the first copy is fully off-screen, at which point
  /// the second copy is exactly at the starting position.
  double _loopScrollDistance(double textWidth) {
    return textWidth + widget.gapWidth;
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  void _ensureMeasured(TextScaler textScaler) {
    if (_cachedTextWidth != null && _cachedTextScaler == textScaler) {
      return;
    }
    _cachedTextScaler = textScaler;
    _cachedTextWidth = AdaptiveMarqueeText.measureTextWidth(
      text: widget.text,
      style: widget.style,
      textScaler: textScaler,
    );
  }

  void _scheduleReconfigure() {
    if (_reconfigureScheduled) return;
    _reconfigureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _reconfigureScheduled = false;
      if (!mounted) return;
      _reconfigureAndStart();
    });
  }

  void _reconfigureAndStart() {
    final textWidth = _cachedTextWidth;
    final containerWidth = _containerWidth;
    if (textWidth == null || containerWidth == null) {
      _controller.stop();
      _controller.value = 0;
      _generation++;
      _initialPauseComplete = false;
      return;
    }

    if (textWidth <= containerWidth) {
      _controller.stop();
      _controller.value = 0;
      _generation++;
      _initialPauseComplete = false;
      return;
    }

    final scrollDistance = _loopScrollDistance(textWidth);

    // Duration based on scrolling the full loop distance at the given velocity
    final durationMs =
        (scrollDistance / widget.velocity * 1000).round().clamp(2000, 60000);

    _controller
      ..stop()
      ..duration = Duration(milliseconds: durationMs)
      ..value = 0;

    _generation++;
    _initialPauseComplete = false;
    _runLoop(_generation);
  }

  Future<void> _runLoop(int generation) async {
    if (!mounted || generation != _generation) return;

    // Initial pause before scrolling starts
    await Future<void>.delayed(widget.startPause);
    if (!mounted || generation != _generation) return;

    _initialPauseComplete = true;

    // Start continuous repeating animation
    _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    _ensureMeasured(textScaler);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return SizedBox(height: widget.height);
        }

        final previousContainerWidth = _containerWidth;
        if (previousContainerWidth == null ||
            (previousContainerWidth - maxWidth).abs() > _widthEpsilon) {
          _containerWidth = maxWidth;
          _scheduleReconfigure();
        }

        final rawTextWidth = _cachedTextWidth ?? 0;
        if (rawTextWidth <= maxWidth) {
          return SizedBox(
            height: widget.height,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.text,
                style: widget.style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
              ),
            ),
          );
        }

        // Add buffer to prevent clipping from measurement inaccuracies
        final textWidth = rawTextWidth + _textWidthBuffer;
        final scrollDistance = _loopScrollDistance(textWidth);
        final totalRowWidth = (textWidth * 2) + widget.gapWidth;

        return RepaintBoundary(
          child: ClipRect(
            child: SizedBox(
              width: maxWidth,
              height: widget.height,
              child: AnimatedBuilder(
                animation: _controller,
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  child: SizedBox(
                    width: totalRowWidth,
                    child: Row(
                      children: [
                        // First copy of the text
                        SizedBox(
                          width: textWidth,
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: 0,
                            maxWidth: double.infinity,
                            child: Text(
                              widget.text,
                              style: widget.style,
                              maxLines: 1,
                              overflow: TextOverflow.visible,
                              softWrap: false,
                              textAlign: TextAlign.start,
                            ),
                          ),
                        ),
                        // Gap between copies
                        SizedBox(width: widget.gapWidth),
                        // Second copy of the text (for seamless loop)
                        SizedBox(
                          width: textWidth,
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: 0,
                            maxWidth: double.infinity,
                            child: Text(
                              widget.text,
                              style: widget.style,
                              maxLines: 1,
                              overflow: TextOverflow.visible,
                              softWrap: false,
                              textAlign: TextAlign.start,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                builder: (context, child) {
                  // Only apply translation after initial pause is complete
                  final offset = _initialPauseComplete
                      ? -scrollDistance * _controller.value
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
