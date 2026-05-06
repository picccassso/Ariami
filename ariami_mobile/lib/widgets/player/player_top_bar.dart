import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../common/mini_player_aware_bottom_sheet.dart';

/// Top bar for full player screen with minimize button.
class PlayerTopBar extends StatelessWidget {
  final VoidCallback onMinimize;
  final VoidCallback? onOpenQueue;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;

  const PlayerTopBar({
    super.key,
    required this.onMinimize,
    this.onOpenQueue,
    this.onPlayNext,
    this.onAddToQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: onMinimize,
            tooltip: 'Back',
            iconSize: 32,
          ),
          Expanded(
            child: Text(
              'Now Playing',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          if (onPlayNext != null || onAddToQueue != null)
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () => _showOptionsSheet(context),
              tooltip: 'More options',
            )
          else
            const SizedBox(width: 48, height: 48),
        ],
      ),
    );
  }

  Future<void> _showOptionsSheet(BuildContext context) {
    return showAriamiSheet<void>(
      context: context,
      header: const AriamiSheetHeader(title: 'Song Options'),
      items: [
        if (onPlayNext != null)
          ListTile(
            leading: const Icon(Icons.skip_next_rounded),
            title: const Text('Play next'),
            onTap: () {
              Navigator.pop(context);
              onPlayNext?.call();
            },
          ),
        if (onAddToQueue != null)
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: const Text('Add to queue'),
            onTap: () {
              Navigator.pop(context);
              onAddToQueue?.call();
            },
          ),
      ],
    );
  }
}
