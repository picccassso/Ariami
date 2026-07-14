import 'dart:ui';

/// Holds the extracted colors for player gradient backgrounds
class GradientColors {
  /// Primary dominant color (used at gradient center/start)
  final Color primary;

  /// Secondary color (used for gradient middle/transition)
  final Color secondary;

  /// Optional accent color (for highlights)
  final Color? accent;

  /// Artwork colour selected specifically for whole-app dynamic theming.
  ///
  /// Player gradients keep using [primary], while the app theme can prefer a
  /// vibrant swatch without changing the established player artwork treatment.
  final Color? themeSeed;

  const GradientColors({
    required this.primary,
    required this.secondary,
    this.accent,
    this.themeSeed,
  });

  /// Default fallback gradient colors (grey tones)
  static const GradientColors fallback = GradientColors(
    primary: Color(0xFF2A2A2A),
    secondary: Color(0xFF1A1A1A),
    accent: Color(0xFF3A3A3A),
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GradientColors &&
        other.primary == primary &&
        other.secondary == secondary &&
        other.accent == accent &&
        other.themeSeed == themeSeed;
  }

  @override
  int get hashCode => Object.hash(primary, secondary, accent, themeSeed);
}
