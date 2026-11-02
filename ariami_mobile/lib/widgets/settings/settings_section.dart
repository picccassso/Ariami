import 'package:flutter/material.dart';

import 'settings_header.dart';

/// One section of a settings page: a ruled, sentence-case [SettingsHeader]
/// over its tiles. Sections are separated by rules rather than boxed as
/// cards, as on Premium Desktop.
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [SettingsHeader(title), ...tiles],
      ),
    );
  }
}
