import 'package:flutter/material.dart';

/// Secondary controls row (Queue, Add to Playlist)
class PlayerSecondaryControls extends StatelessWidget {
  final VoidCallback? onOpenQueue;
  final VoidCallback? onAddToPlaylist;

  const PlayerSecondaryControls({
    super.key,
    this.onOpenQueue,
    this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Add to playlist button
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: onAddToPlaylist ?? () {},
            tooltip: 'Add to playlist',
            iconSize: 24,
          ),

          const SizedBox(width: 8),

          // Queue button
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: onOpenQueue,
            tooltip: 'View queue',
            iconSize: 24,
          ),
        ],
      ),
    );
  }
}
