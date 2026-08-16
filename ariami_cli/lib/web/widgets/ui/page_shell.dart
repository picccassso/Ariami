import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/layout.dart';

/// Centres page content in a readable column on the app's gradient canvas.
///
/// Every screen goes through this so the dashboard, the setup flow and the
/// login page all share one measure and one set of gutters instead of running
/// edge to edge on a wide monitor.
class PageShell extends StatelessWidget {
  const PageShell({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.contentMaxWidth,
    this.scrollable = true,
    this.centerVertically = false,
    this.verticalPadding,
  });

  final Widget child;
  final double maxWidth;

  /// When false the child is laid out at full height (for screens that own
  /// their own scrolling, such as a hero panel).
  final bool scrollable;

  /// Centres the column vertically — used by the onboarding screens.
  final bool centerVertically;

  final double? verticalPadding;

  @override
  Widget build(BuildContext context) {
    final widthClass = AppLayout.of(context);
    final gutter = AppLayout.gutter(widthClass);
    final vertical = verticalPadding ??
        (widthClass == WidthClass.compact ? 20.0 : 32.0);

    final column = Align(
      alignment: centerVertically ? Alignment.center : Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: gutter,
            vertical: vertical,
          ),
          child: child,
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: scrollable
          // A bare Align inside a scroll view shrink-wraps its child, so
          // `centerVertically` would centre within the content's own height
          // and appear pinned to the top. Give the scroll child a minimum
          // height of the viewport so short pages actually centre, while
          // long ones still scroll.
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: column,
                ),
              ),
            )
          : column,
    );
  }
}
