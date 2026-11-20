import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// A rounded surface whose colours follow the active theme *instantly* while a
/// hover / selection highlight still fades in and out.
///
/// Why this exists: an [AnimatedContainer] whose `color` is a theme value (e.g.
/// `context.colors.surfaceHigh`) re-animates whenever that value changes. During
/// the app-wide theme transition the palette is interpolated every frame, so
/// each of those containers chases a moving target over its *own* (shorter)
/// duration and settles at a different time than its neighbours — the UI recolours
/// "one panel at a time".
///
/// [HoverSurface] separates the two concerns. The [base] and [highlight] colours
/// are read fresh on every build, so when the root theme animates they all move
/// together in lockstep. Only the highlight's *opacity* is implicitly animated,
/// and that is independent of the theme. Because [highlight] is painted opaque on
/// top of [base], the cross-fade looks identical to lerping straight between the
/// two colours.
class HoverSurface extends StatelessWidget {
  const HoverSurface({
    super.key,
    required this.active,
    required this.base,
    required this.highlight,
    required this.borderRadius,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.width,
    this.cursor = SystemMouseCursors.click,
  });

  final bool active;

  final Color base;

  final Color highlight;

  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  final double? width;

  final MouseCursor? cursor;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: base)),
            Positioned.fill(
              child: AnimatedOpacity(
                duration: Motion.fast,
                curve: Motion.standard,
                opacity: active ? 1 : 0,
                child: ColoredBox(color: highlight),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );

    if (cursor != null) {
      return MouseRegion(
        cursor: cursor!,
        child: surface,
      );
    }
    return surface;
  }
}
