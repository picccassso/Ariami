import 'package:flutter/material.dart';
import '../../models/repeat_mode.dart' as playback_repeat;

/// Playback controls widget with play/pause, skip, shuffle, and repeat buttons
class PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final bool isShuffleEnabled;
  final playback_repeat.RepeatMode repeatMode;
  final bool hasNext;
  final bool hasPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipNext;
  final VoidCallback onSkipPrevious;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;

  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.isLoading,
    required this.isShuffleEnabled,
    required this.repeatMode,
    required this.hasNext,
    required this.hasPrevious,
    required this.onPlayPause,
    required this.onSkipNext,
    required this.onSkipPrevious,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Shuffle button
        IconButton(
          icon: const Icon(Icons.shuffle),
          iconSize: 28,
          onPressed: onToggleShuffle,
          tooltip: isShuffleEnabled ? 'Shuffle: On' : 'Shuffle: Off',
          style: isShuffleEnabled
              ? IconButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                )
              : null,
        ),

        // Previous button
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: 36,
          onPressed: hasPrevious ? onSkipPrevious : null,
          tooltip: 'Previous',
        ),

        // Play/Pause button (larger, prominent)
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primary,
          ),
          child: isLoading
              ? Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  iconSize: 36,
                  onPressed: onPlayPause,
                  tooltip: isPlaying ? 'Pause' : 'Play',
                ),
        ),

        // Next button
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: 36,
          onPressed: hasNext ? onSkipNext : null,
          tooltip: 'Next',
        ),

        // Repeat button
        IconButton(
          icon: Icon(
            repeatMode == playback_repeat.RepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
          ),
          iconSize: 28,
          onPressed: onToggleRepeat,
          tooltip: 'Repeat: ${repeatMode.displayName}',
          style: repeatMode != playback_repeat.RepeatMode.none
              ? IconButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                )
              : null,
        ),
      ],
    );
  }
}
