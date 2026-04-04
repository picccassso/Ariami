import 'package:flutter/material.dart';
import '../../models/repeat_mode.dart' as playback_repeat;

/// Secondary controls row (Shuffle, Repeat, Queue, Add to Playlist)
class PlayerSecondaryControls extends StatelessWidget {
  final bool isShuffleEnabled;
  final playback_repeat.RepeatMode repeatMode;
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
            icon: const Icon(Icons.shuffle_rounded),
            onPressed: onToggleShuffle,
            tooltip: isShuffleEnabled ? 'Shuffle on' : 'Shuffle off',
            iconSize: 24,
            style: isShuffleEnabled
                ? IconButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.primary.withOpacity(0.2),
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
            style: repeatMode != playback_repeat.RepeatMode.none
                ? IconButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  )
                : null,
          ),

          // Queue button
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: onOpenQueue,
            tooltip: 'View queue',
            iconSize: 24,
          ),

          // Add to playlist button
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: onAddToPlaylist ?? () {},
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
      case playback_repeat.RepeatMode.none:
        return Icons.repeat_rounded;
      case playback_repeat.RepeatMode.all:
        return Icons.repeat_rounded;
      case playback_repeat.RepeatMode.one:
        return Icons.repeat_one_rounded;
    }
  }

  /// Get repeat mode tooltip
  String _getRepeatTooltip() {
    switch (repeatMode) {
      case playback_repeat.RepeatMode.none:
        return 'Repeat off';
      case playback_repeat.RepeatMode.all:
        return 'Repeat all';
      case playback_repeat.RepeatMode.one:
        return 'Repeat one';
    }
  }
}
