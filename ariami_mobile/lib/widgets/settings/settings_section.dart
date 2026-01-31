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
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111111) : const Color(0xFFF9F9F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
                width: 1,
              ),
            ),
            child: Column(
              children: List.generate(
                tiles.length,
                (index) => Column(
                  children: [
                    tiles[index],
                    if (index < tiles.length - 1)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 16,
                        endIndent: 16,
                        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
