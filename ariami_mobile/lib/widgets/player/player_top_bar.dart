import 'package:flutter/material.dart';

/// Top bar for full player screen with minimize button and overflow menu
class PlayerTopBar extends StatelessWidget {
  final VoidCallback onMinimize;
  final VoidCallback? onOpenQueue;

  const PlayerTopBar({
    super.key,
    required this.onMinimize,
    this.onOpenQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Minimize button
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: onMinimize,
            tooltip: 'Minimize',
            iconSize: 32,
          ),

          // "Now Playing" text
          Text(
            'Now Playing',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),

          // Overflow menu
          IconButton(
            icon: const Icon(Icons.more_vert),
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
        return SafeArea(
          minimum: EdgeInsets.only(
            bottom: 64 +
                kBottomNavigationBarHeight, // Mini player + download bar + nav bar
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onOpenQueue != null)
                ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: const Text('View Queue'),
                  onTap: () {
                    Navigator.pop(context);
                    onOpenQueue!();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Add to Playlist'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement in Task 7.5
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
