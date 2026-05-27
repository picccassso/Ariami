import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../common/mini_player_aware_bottom_sheet.dart';

/// Secondary controls row (Cast, Queue, Add to Playlist)
class PlayerSecondaryControls extends StatelessWidget {
  final Widget? castButton;
  final VoidCallback? onOpenQueue;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;

  const PlayerSecondaryControls({
    super.key,
    this.castButton,
    this.onOpenQueue,
    this.onAddToPlaylist,
    this.onPlayNext,
    this.onAddToQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onPlayNext != null || onAddToQueue != null) ...[
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () => _showOptionsSheet(context),
                  tooltip: 'More options',
                  iconSize: 24,
                ),
                const SizedBox(width: 8),
              ],
              castButton ?? const SizedBox(width: 48, height: 48),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.listPlus),
                onPressed: onAddToPlaylist ?? () {},
                tooltip: 'Add to playlist',
                iconSize: 24,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(LucideIcons.listMusic),
                onPressed: onOpenQueue,
                tooltip: 'View queue',
                iconSize: 24,
              ),
            ],
          ),
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
