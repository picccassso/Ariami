import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Displays single-line text that scrolls horizontally when it overflows.
///
/// Overflowing text rests at its start with an ellipsis and only scrolls while
/// the mouse is over it. Every frame of a scroll redraws the whole window on
/// Windows, which a maximised window pays for in GPU time.
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
class AdaptiveMarqueeSpan extends StatefulWidget {
  final InlineSpan span;
  final TextStyle? style;

  final double velocity;
  final Duration startPause;

  final double gapWidth;

  const AdaptiveMarqueeSpan({
    super.key,
    required this.span,
    this.style,
    this.velocity = 30.0,
    this.startPause = const Duration(milliseconds: 500),
    this.gapWidth = 48.0,
  });

  static TextPainter createTextPainter({
    required InlineSpan span,
    required TextStyle? style,
    required TextScaler textScaler,
  }) {
    return TextPainter(
      text: span,
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
  }

  static Size measureTextSize({
    required InlineSpan span,
    required TextStyle? style,
    required TextScaler textScaler,
  }) {
    return createTextPainter(
      span: span,
      style: style,
      textScaler: textScaler,
    ).size;
  }

  @override
  State<AdaptiveMarqueeSpan> createState() => _AdaptiveMarqueeSpanState();
}

class _AdaptiveMarqueeSpanState extends State<AdaptiveMarqueeSpan>
    with SingleTickerProviderStateMixin {
  static const double _widthEpsilon = 0.5;

  /// Buffer added to measured text width to prevent clipping from font
  /// rendering differences between TextPainter measurement and Text widget.
  static const double _textWidthBuffer = 12.0;

  static const double _heightPadding = 6.0;

  late final AnimationController _controller;
  Size? _cachedTextSize;
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

  bool _tickersEnabled = true;
  bool _hovered = false;

  // A muted subtree (idle or minimised window) rests even under the mouse.
  bool get _scrolling => _hovered && _tickersEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled == _tickersEnabled) return;
    _tickersEnabled = enabled;
    _scheduleReconfigure();
  }

  void _setHovered(bool hovered) {
    setState(() => _hovered = hovered);
    _scheduleReconfigure();
  }

  @override
  void didUpdateWidget(AdaptiveMarqueeSpan oldWidget) {
    super.didUpdateWidget(oldWidget);

    final contentChanged =
        oldWidget.span != widget.span || oldWidget.style != widget.style;

    if (contentChanged) {
      _cachedTextSize = null;
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
    if (_cachedTextSize != null && _cachedTextScaler == textScaler) {
      return;
    }
    _cachedTextScaler = textScaler;
    _cachedTextSize = AdaptiveMarqueeSpan.measureTextSize(
      span: widget.span,
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
    final textWidth = _cachedTextSize?.width;
    final containerWidth = _containerWidth;
    if (textWidth == null ||
        containerWidth == null ||
        textWidth <= containerWidth ||
        !_scrolling) {
      _controller.stop();
      _controller.value = 0;
      _generation++;
      _initialPauseComplete = false;
      return;
    }

    final scrollDistance = _loopScrollDistance(textWidth);

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

    await Future<void>.delayed(widget.startPause);
    if (!mounted || generation != _generation) return;

    _initialPauseComplete = true;

    _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    _ensureMeasured(textScaler);

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          if (!maxWidth.isFinite || maxWidth <= 0) {
            return const SizedBox.shrink();
          }

          final previousContainerWidth = _containerWidth;
          if (previousContainerWidth == null ||
              (previousContainerWidth - maxWidth).abs() > _widthEpsilon) {
            _containerWidth = maxWidth;
            _scheduleReconfigure();
          }

          final rawTextWidth = _cachedTextSize?.width ?? 0;
          // Extra room so descenders and hover underlines aren't clipped.
          final textHeight = (_cachedTextSize?.height ?? 16.0) + _heightPadding;
          if (rawTextWidth <= maxWidth || !_scrolling) {
            return SizedBox(
              height: textHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  widget.span,
                  style: widget.style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                ),
              ),
            );
          }

          final textWidth = rawTextWidth + _textWidthBuffer;
          final scrollDistance = _loopScrollDistance(textWidth);
          final totalRowWidth = (textWidth * 2) + widget.gapWidth;

          return RepaintBoundary(
            child: ClipRect(
              child: SizedBox(
                width: maxWidth,
                height: textHeight,
                child: AnimatedBuilder(
                  animation: _controller,
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    minHeight: textHeight,
                    maxHeight: textHeight,
                    child: SizedBox(
                      width: totalRowWidth,
                      height: textHeight,
                      child: Row(
                        children: [
                          SizedBox(
                            width: textWidth,
                            height: textHeight,
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: 0,
                              maxWidth: double.infinity,
                              minHeight: textHeight,
                              maxHeight: textHeight,
                              child: Text.rich(
                                widget.span,
                                style: widget.style,
                                maxLines: 1,
                                overflow: TextOverflow.visible,
                                softWrap: false,
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ),
                          SizedBox(width: widget.gapWidth, height: textHeight),
                          SizedBox(
                            width: textWidth,
                            height: textHeight,
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: 0,
                              maxWidth: double.infinity,
                              minHeight: textHeight,
                              maxHeight: textHeight,
                              child: Text.rich(
                                widget.span,
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
      ),
    );
  }
}
