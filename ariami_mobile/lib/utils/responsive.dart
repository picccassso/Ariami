import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Minimum window width at which the app switches to tablet ("expanded")
/// layouts: navigation rail, denser grids, width-capped content columns.
const double kTabletBreakpoint = 600.0;

/// Maximum width of setup/auth form columns on wide screens.
const double kSetupContentMaxWidth = 480.0;

/// Maximum width of list-style content (settings, search, queue) on wide
/// screens.
const double kListContentMaxWidth = 720.0;

/// Maximum width of modal bottom sheets on wide screens.
const double kBottomSheetMaxWidth = 640.0;

/// Upper bound on album/playlist grid tile width. Grids derive their column
/// count from this, so wider screens gain columns instead of bigger cards.
const double kGridMaxTileExtent = 240.0;

/// Whether the window is wide enough for tablet layouts (navigation rail,
/// side-by-side player).
bool isExpandedWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kTabletBreakpoint;

/// Expanded height for the square-ish artwork headers on the album/playlist
/// detail screens. Tracks screen width on phones (unchanged behavior), but
/// never exceeds half the viewport height, so landscape/tablet headers don't
/// swallow the whole screen.
double detailHeaderHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final byWidth = size.width.clamp(200.0, 600.0);
  return math.max(200.0, math.min(byWidth, size.height * 0.5));
}

/// Grid delegate for album/playlist card grids that scales the column count
/// with the available width instead of hard-coding 2-3 columns.
SliverGridDelegate responsiveCardGridDelegate({
  double childAspectRatio = 0.75,
  double spacing = 16.0,
}) {
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: kGridMaxTileExtent,
    childAspectRatio: childAspectRatio,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
  );
}

/// Centers [child] horizontally and caps its width on wide screens. On phones
/// (available width <= [maxWidth]) this is a pass-through.
class ContentWidthLimiter extends StatelessWidget {
  const ContentWidthLimiter({
    super.key,
    this.maxWidth = kListContentMaxWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
