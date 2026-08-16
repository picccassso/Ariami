import 'package:flutter/widgets.dart';

/// Width classes for the dashboard. This UI is opened in a browser on
/// anything from a phone to an ultrawide monitor, so every screen resolves its
/// spacing and column count from these rather than from raw pixel checks.
enum WidthClass {
  /// Phones and narrow splits: single column, tighter gutters.
  compact,

  /// Tablets and half-screen windows: two columns where it helps.
  medium,

  /// Full desktop windows: the content column reaches its maximum width.
  expanded,
}

class AppLayout {
  const AppLayout._();

  /// The reading column never grows past this. Without it the dashboard
  /// stretches edge to edge on a wide monitor and a single IP address ends up
  /// alone on a 1900px row.
  static const double contentMaxWidth = 1040;

  /// Narrower cap for focused, single-purpose screens (login, owner setup).
  static const double formMaxWidth = 460;

  /// Cap for the onboarding screens, which are centred prose plus one action.
  static const double proseMaxWidth = 560;

  static const double compactBreakpoint = 700;
  static const double mediumBreakpoint = 1100;

  static WidthClass classify(double width) {
    if (width < compactBreakpoint) return WidthClass.compact;
    if (width < mediumBreakpoint) return WidthClass.medium;
    return WidthClass.expanded;
  }

  static WidthClass of(BuildContext context) =>
      classify(MediaQuery.sizeOf(context).width);

  /// Horizontal page gutter for a width class.
  static double gutter(WidthClass widthClass) => switch (widthClass) {
        WidthClass.compact => 16,
        WidthClass.medium => 24,
        WidthClass.expanded => 32,
      };

  /// Vertical space between major sections.
  static double sectionGap(WidthClass widthClass) =>
      widthClass == WidthClass.compact ? 28 : 36;

  /// Columns for the stat grid, chosen from the width actually available to
  /// the grid rather than the window — inside the capped content column those
  /// are different numbers, and the window's thresholds give one column too
  /// few.
  static int statColumnsForContentWidth(double width) {
    if (width >= 780) return 3;
    if (width >= 460) return 2;
    return 1;
  }
}
