import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Top bar for full player screen with minimize button and overflow menu
class PlayerTopBar extends StatelessWidget {
  final VoidCallback onMinimize;
  final VoidCallback? onOpenQueue;
  final Widget? castButton;

  const PlayerTopBar({
    super.key,
    required this.onMinimize,
    this.onOpenQueue,
    this.castButton,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          // Minimize button
          IconButton(
            icon: const Icon(LucideIcons.chevronDown),
            onPressed: onMinimize,
            tooltip: 'Minimize',
            iconSize: 32,
          ),

          // "Now Playing" text
          Expanded(
            child: Text(
              'Now Playing',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),

          if (castButton != null) castButton!,

          // Overflow menu
          IconButton(
            icon: const Icon(LucideIcons.moreVertical),
            onPressed: () => _showOverflowMenu(context),
            tooltip: 'More options',
          ),
        ],
      ),
    );
  }

  /// Show overflow menu with additional options
  void _showOverflowMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onOpenQueue != null)
              ListTile(
                leading: const Icon(LucideIcons.listMusic),
                title: const Text('View Queue'),
                onTap: () {
                  Navigator.pop(context);
                  onOpenQueue!();
                },
              ),
            ListTile(
              leading: const Icon(LucideIcons.listPlus),
              title: const Text('Add to Playlist'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement in Task 7.5
              },
            ),
          ],
        );
      },
    );
  }
}
