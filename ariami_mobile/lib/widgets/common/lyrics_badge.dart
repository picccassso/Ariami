import 'package:flutter/material.dart';

/// Compact inline pill badge displaying "LYRICS" next to track titles.
class LyricsBadge extends StatelessWidget {
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const LyricsBadge({
    super.key,
    this.fontSize = 8.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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
        'LYRICS',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: colorScheme.onSurface.withValues(alpha: 0.7),
          height: 1.1,
        ),
      ),
    );
  }
}
