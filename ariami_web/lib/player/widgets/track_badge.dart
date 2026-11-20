import 'package:flutter/material.dart';

import '../theme/player_theme.dart';

/// Compact pill before a track's artist: "LYRICS" when the track has
/// lyrics, otherwise "INST" when it is instrumental, otherwise nothing.
class TrackBadge extends StatelessWidget {
  final bool hasLyrics;
  final bool isInstrumental;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const TrackBadge({
    super.key,
    required this.hasLyrics,
    required this.isInstrumental,
    this.fontSize = 8.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
  });

  @override
  Widget build(BuildContext context) {
    final label = hasLyrics ? 'LYRICS' : (isInstrumental ? 'INST' : null);
    if (label == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: padding,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: context.colors.textSecondary,
          height: 1.1,
        ),
      ),
    );
  }
}
