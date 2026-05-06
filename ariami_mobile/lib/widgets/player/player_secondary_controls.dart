import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Secondary controls row (Cast, Queue, Add to Playlist)
class PlayerSecondaryControls extends StatelessWidget {
  final Widget? castButton;
  final VoidCallback? onOpenQueue;
  final VoidCallback? onAddToPlaylist;

  const PlayerSecondaryControls({
    super.key,
    this.castButton,
    this.onOpenQueue,
    this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          castButton ?? const SizedBox(width: 48, height: 48),
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
}
