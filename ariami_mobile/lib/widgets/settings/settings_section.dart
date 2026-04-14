import 'package:flutter/material.dart';

/// A reusable settings section widget
/// Groups multiple settings tiles under a title with consistent styling
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> tiles;

  const SettingsSection({
    super.key,
    required this.title,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Column(
            children: List.generate(
              tiles.length,
              (index) => tiles[index],
            ),
          ),
        ],
      ),
    );
  }
}
