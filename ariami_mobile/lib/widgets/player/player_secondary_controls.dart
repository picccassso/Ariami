import 'package:flutter/material.dart';
import '../../models/repeat_mode.dart';

/// Secondary controls row (Shuffle, Repeat, Queue, Add to Playlist)
class PlayerSecondaryControls extends StatelessWidget {
  final bool isShuffleEnabled;
  final RepeatMode repeatMode;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;
  final VoidCallback? onOpenQueue;
  final VoidCallback? onAddToPlaylist;

  const PlayerSecondaryControls({
    super.key,
    required this.isShuffleEnabled,
    required this.repeatMode,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
    this.onOpenQueue,
    this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Shuffle button
          IconButton(
            icon: const Icon(Icons.shuffle),
            onPressed: onToggleShuffle,
            tooltip: isShuffleEnabled ? 'Shuffle on' : 'Shuffle off',
            iconSize: 24,
            style: isShuffleEnabled
                ? IconButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  )
                : null,
          ),

          // Repeat button
          IconButton(
            icon: Icon(_getRepeatIcon()),
            onPressed: onToggleRepeat,
            tooltip: _getRepeatTooltip(),
            iconSize: 24,
            style: repeatMode != RepeatMode.none
                ? IconButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  )
                : null,
          ),

          // Queue button
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: onOpenQueue,
            tooltip: 'View queue',
            iconSize: 24,
          ),

          // Add to playlist button
          IconButton(
            icon: const Icon(Icons.playlist_add),
            onPressed: onAddToPlaylist ?? () {
              // TODO: Implement in Task 7.5
            },
            tooltip: 'Add to playlist',
            iconSize: 24,
          ),
        ],
      ),
    );
  }

  /// Get repeat mode icon
  IconData _getRepeatIcon() {
    switch (repeatMode) {
      case RepeatMode.none:
        return Icons.repeat;
      case RepeatMode.all:
        return Icons.repeat;
      case RepeatMode.one:
        return Icons.repeat_one;
    }
  }

  /// Get repeat mode tooltip
  String _getRepeatTooltip() {
    switch (repeatMode) {
      case RepeatMode.none:
        return 'Repeat off';
      case RepeatMode.all:
        return 'Repeat all';
      case RepeatMode.one:
        return 'Repeat one';
    }
  }
}
