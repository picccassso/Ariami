import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/player_theme.dart';

/// A horizontal card rail with a hover-reveal scrubber and paging arrows.
///
/// The rail deliberately doesn't react to wheel/drag scrolling — that fought
/// the page's own vertical scroll. It moves only via the scrubber underneath
/// or the half-opaque arrows overlaid on its edges; wheel events fall through
/// and scroll the page. Used by the home view's "Jump back in" and "Pinned"
/// sections.
class ScrollRail extends StatefulWidget {
  const ScrollRail({
    super.key,
    required this.child,
    this.revealScrubber = false,
  });

  final Widget child;

  /// Forces the scrubber visible — lets a parent hover region (e.g. one that
  /// also covers the section header) reveal it beyond the rail's own hover.
  final bool revealScrubber;

  @override
  State<ScrollRail> createState() => _ScrollRailState();
}

class _ScrollRailState extends State<ScrollRail> {
  final ScrollController _scroll = ScrollController();

  bool _hovering = false;
  bool _dragging = false;

  // Mirrored scroll metrics, kept via notifications so the scrubber and
  // arrows can render without poking at the controller during build.
  double _maxExtent = 0;
  double _viewport = 0;
  double _offset = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _syncMetrics(ScrollMetrics metrics) {
    if (metrics.maxScrollExtent == _maxExtent &&
        metrics.viewportDimension == _viewport &&
        metrics.pixels == _offset) {
      return;
    }
    setState(() {
      _maxExtent = metrics.maxScrollExtent;
      _viewport = metrics.viewportDimension;
      _offset = metrics.pixels;
    });
  }

  /// Pages the rail by most of a viewport, so the last visible card stays on
  /// screen as an anchor.
  void _page(int direction) {
    if (!_scroll.hasClients || _maxExtent <= 0) return;
    final target =
        (_scroll.offset + direction * _viewport * 0.85).clamp(0.0, _maxExtent);
    _scroll.animateTo(target, duration: Motion.medium, curve: Motion.standard);
  }

  Widget _buildArrow({required bool left}) {
    // Each arrow disappears once its direction is exhausted, so the pair also
    // doubles as an "there's more this way" hint.
    final canScroll = left ? _offset > 1 : _offset < _maxExtent - 1;
    return AnimatedOpacity(
      duration: Motion.fast,
      opacity: canScroll ? 1 : 0,
      child: IgnorePointer(
        ignoring: !canScroll,
        child: Material(
          color: Colors.black.withValues(alpha: 0.5),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _page(left ? -1 : 1),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                size: 28,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Custom scrubber instead of a [Scrollbar]: the stock scrollbar won't drag
  /// a scrollable with [NeverScrollableScrollPhysics], and we want the rail to
  /// move *only* via this bar (wheel events must keep scrolling the page).
  /// Fades in while the pointer is over the rail, away it disappears.
  Widget _buildScrubber(BuildContext context) {
    if (_maxExtent <= 0 || _viewport <= 0) return const SizedBox.shrink();
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          final content = _maxExtent + _viewport;
          final thumbWidth =
              (trackWidth * _viewport / content).clamp(40.0, trackWidth);
          final range = trackWidth - thumbWidth;
          final x =
              range <= 0 ? 0.0 : (_offset / _maxExtent).clamp(0.0, 1.0) * range;
          return AnimatedOpacity(
            duration: Motion.fast,
            opacity: (widget.revealScrubber || _hovering || _dragging) ? 1 : 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => setState(() => _dragging = true),
              onHorizontalDragEnd: (_) => setState(() => _dragging = false),
              onHorizontalDragCancel: () => setState(() => _dragging = false),
              onHorizontalDragUpdate: (details) {
                if (range <= 0) return;
                final delta = details.delta.dx * (_maxExtent / range);
                _scroll.jumpTo(
                  (_scroll.offset + delta).clamp(0.0, _maxExtent),
                );
              },
              onTapDown: (details) {
                if (range <= 0) return;
                final target =
                    ((details.localPosition.dx - thumbWidth / 2) / range) *
                        _maxExtent;
                _scroll.jumpTo(target.clamp(0.0, _maxExtent));
              },
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.colors.surfaceHigh,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: _dragging ? Duration.zero : Motion.fast,
                    left: x,
                    top: 4,
                    child: Container(
                      width: thumbWidth,
                      height: 6,
                      decoration: BoxDecoration(
                        color: context.colors.textPrimary
                            .withValues(alpha: _dragging ? 0.5 : 0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              NotificationListener<ScrollMetricsNotification>(
                onNotification: (notification) {
                  _syncMetrics(notification.metrics);
                  return false;
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    _syncMetrics(notification.metrics);
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: widget.child,
                  ),
                ),
              ),
              if (_maxExtent > 0) ...[
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(child: _buildArrow(left: true)),
                ),
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(child: _buildArrow(left: false)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          _buildScrubber(context),
        ],
      ),
    );
  }
}
