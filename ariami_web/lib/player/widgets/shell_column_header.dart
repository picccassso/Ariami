import 'package:flutter/material.dart';

import '../services/player_host.dart';
import '../theme/player_theme.dart';

/// Height of every shell column's header row, so the sidebar, top bar and
/// right panel share one baseline and one continuous rule beneath it.
const double kShellHeaderHeight = 52;

/// A shell column's header row: [kShellHeaderHeight] tall over a hairline
/// rule. On desktop macOS, where the native title bar is hidden, its empty
/// space drags the window via [PlayerHost.windowDragAreaBuilder].
class ShellColumnHeader extends StatelessWidget {
  const ShellColumnHeader({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final host = maybeReadHost(context);
    return Container(
      height: kShellHeaderHeight,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (host != null &&
              host.hasMacWindowChrome &&
              host.windowDragAreaBuilder != null)
            Positioned.fill(
              child: host.windowDragAreaBuilder!(const SizedBox.expand()),
            ),
          Padding(
            padding: padding,
            child: Row(children: children),
          ),
        ],
      ),
    );
  }
}

/// A plain text tab, underlined in ink while selected — the shell's one tab
/// style, used instead of pills.
class ShellTab extends StatelessWidget {
  const ShellTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.height = kShellHeaderHeight - 1,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The strip it sits in, less that strip's rule, so the underline lands
  /// on the rule.
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.transparent,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? colors.textPrimary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          // Hugs the label; squeezed below that, the label clips rather
          // than wrapping.
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
