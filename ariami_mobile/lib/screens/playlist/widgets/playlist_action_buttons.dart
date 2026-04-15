import 'package:flutter/material.dart';

/// Action buttons for playlist (Play, Shuffle, Reorder, Add)
class PlaylistActionButtons extends StatelessWidget {
  /// Whether there are songs to play
  final bool hasSongs;

  /// Whether there are enough songs to reorder (>1)
  final bool canReorder;

  /// Current reorder mode state
  final bool isReorderMode;

  /// Callback when Play button is pressed
  final VoidCallback? onPlay;

  /// Callback when Shuffle button is pressed
  final VoidCallback? onShuffle;

  /// Callback when Reorder button is pressed (toggles mode)
  final VoidCallback? onToggleReorder;

  /// Callback when Add Songs button is pressed
  final VoidCallback? onAddSongs;

  const PlaylistActionButtons({
    super.key,
    required this.hasSongs,
    required this.canReorder,
    required this.isReorderMode,
    this.onPlay,
    this.onShuffle,
    this.onToggleReorder,
    this.onAddSongs,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side: Secondary actions
          Row(
            children: [
              IconButton(
                icon: Icon(
                  isReorderMode ? Icons.check_rounded : Icons.reorder_rounded,
                  color: isReorderMode
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: canReorder ? onToggleReorder : null,
                iconSize: 28,
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: onAddSongs,
                iconSize: 28,
              ),
            ],
          ),

          // Right side: Play and Shuffle
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: hasSongs ? onShuffle : null,
                iconSize: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              // Big Play Button
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  color: Theme.of(context).colorScheme.onPrimary,
                  iconSize: 36,
                  onPressed: hasSongs ? onPlay : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
