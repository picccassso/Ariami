import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/player_theme.dart';
import 'settings_widgets.dart' show SettingsLabel;

enum SettingsSection {
  general('General', Icons.tune_rounded),
  appearance('Appearance', Icons.palette_rounded),
  playback('Playback', Icons.headphones_rounded),
  downloads('Downloads', Icons.download_rounded),
  listeningStats('Listening stats', Icons.equalizer_rounded),
  updates('Updates', Icons.system_update_alt_rounded),
  account('Account', Icons.person_rounded),
  license('License', Icons.key_rounded),
  // Must stay above serverOverview: [isServer] is an index comparison.
  hiddenItems('My Library', Icons.library_music_rounded),
  developer('Developer', Icons.bug_report_rounded),
  serverOverview('Overview', Icons.dns_rounded),
  serverActivity('Activity', Icons.timeline_rounded),
  serverUsers('Users', Icons.people_alt_rounded),
  serverConfig('Configuration', Icons.settings_rounded);

  const SettingsSection(this.label, this.icon);
  final String label;
  final IconData icon;

  bool get isServer => index >= serverOverview.index;

  int get serverTab => index - serverOverview.index;
}

class SettingsRailGroupLabel extends StatelessWidget {
  const SettingsRailGroupLabel(this.text, {super.key, required this.compact});
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Divider(color: context.colors.border, height: 16);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 0, 6),
      child: SettingsLabel(text),
    );
  }
}

/// One entry of the settings rail, read like the sidebar's index: plain text,
/// with the open section in ink and marked by a rule on its left edge. The
/// compact rail keeps the icons, with the name on a tooltip.
class SettingsRailItem extends StatelessWidget {
  const SettingsRailItem({
    super.key,
    required this.section,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.textPrimary : colors.textSecondary;
    final Widget label = compact
        ? Tooltip(
            message: section.label,
            child:
                Center(child: Icon(section.icon, size: 18, color: foreground)),
          )
        : AnimatedDefaultTextStyle(
            duration: Motion.fast,
            style: TextStyle(
              fontFamily: PlayerTheme.bodyFamily,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: foreground,
            ),
            child: Text(section.label, overflow: TextOverflow.ellipsis),
          );

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 36,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.only(left: compact ? 0 : 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? colors.textPrimary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: label,
          ),
        ),
      ),
    );
  }
}
