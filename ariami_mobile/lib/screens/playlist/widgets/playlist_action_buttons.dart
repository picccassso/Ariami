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
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          // Primary actions row (Play/Shuffle)
          Row(
            children: [
              // Play All button
              Expanded(
                child: FilledButton.icon(
                  onPressed: hasSongs ? onPlay : null,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text(
                    'Play',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Shuffle button
              Expanded(
                child: FilledButton.icon(
                  onPressed: hasSongs ? onShuffle : null,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  icon: const Icon(Icons.shuffle_rounded, size: 22),
                  label: const Text(
                    'Shuffle',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Secondary actions row (Reorder/Add)
          Row(
            children: [
              // Reorder toggle button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canReorder ? onToggleReorder : null,
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: isReorderMode
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withOpacity(0.5)
                        : null,
                  ),
                  icon: Icon(
                    isReorderMode ? Icons.check_rounded : Icons.reorder_rounded,
                    size: 20,
                  ),
                  label: Text(isReorderMode ? 'Done' : 'Reorder'),
                ),
              ),
              const SizedBox(width: 12),
              // Add songs button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAddSongs,
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Add Songs'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
