import 'package:flutter/material.dart';

/// Bold, letter-spaced section header used on settings-style screens. Text is
/// shown as given. Without [isDark] it uses the theme's onSurface colour;
/// with it, plain white/black.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.text, {super.key, this.isDark});

  final String text;
  final bool? isDark;

  @override
  Widget build(BuildContext context) {
    final dark = isDark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: dark == null
              ? Theme.of(context).colorScheme.onSurface
              : (dark ? Colors.white : Colors.black),
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
