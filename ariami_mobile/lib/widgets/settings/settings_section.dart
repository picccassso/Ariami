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
    final isMaterial = Theme.of(context).platform == TargetPlatform.android;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isMaterial) {
      // Material Design style for Android
      return Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[700],
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 0),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    width: 1,
                  ),
                  bottom: BorderSide(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: List.generate(
                  tiles.length,
                  (index) => Column(
                    children: [
                      tiles[index],
                      if (index < tiles.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 56.0),
                          child: Divider(
                            height: 1,
                            thickness: 0.5,
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // iOS style with grouped appearance
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 0.0, bottom: 8.0),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.3,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                  width: 0.5,
                ),
              ),
              child: Column(
                children: List.generate(
                  tiles.length,
                  (index) => Column(
                    children: [
                      tiles[index],
                      if (index < tiles.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 56.0),
                          child: Divider(
                            height: 1,
                            thickness: 0.5,
                            color: isDark ? Colors.grey[800] : Colors.grey[300],
                          ),
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
}
