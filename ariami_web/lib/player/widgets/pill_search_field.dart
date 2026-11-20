import 'package:flutter/material.dart';

import '../theme/player_theme.dart';

/// Autofocused, pill-shaped search field for the playlist search modes
/// (add songs, reorder via search), styled like the top-bar search.
///
/// A single pill rather than a bare field inside a box: the theme's fill
/// otherwise paints a second box within it.
class PillSearchField extends StatelessWidget {
  const PillSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onKeyEvent,
    required this.onChanged,
    required this.onSubmitted,
    this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final FocusOnKeyEventCallback onKeyEvent;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    OutlineInputBorder pill(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(21),
          borderSide: BorderSide(color: color, width: width),
        );
    return SizedBox(
      height: 42,
      child: Focus(
        onKeyEvent: onKeyEvent,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: TextStyle(fontSize: 14, color: colors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            fillColor: colors.panel,
            hintText: hintText,
            hintStyle: TextStyle(fontSize: 14, color: colors.textSecondary),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 20,
              color: colors.textSecondary,
            ),
            suffixIcon: onClear == null || controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    splashRadius: 18,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onClear,
                  ),
            border: pill(colors.border),
            enabledBorder: pill(colors.border),
            focusedBorder: pill(
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.7),
              1.5,
            ),
          ),
        ),
      ),
    );
  }
}
