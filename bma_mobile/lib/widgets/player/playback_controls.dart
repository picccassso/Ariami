import 'package:flutter/material.dart';
import '../../models/repeat_mode.dart';

/// Playback controls widget with play/pause, skip, shuffle, and repeat buttons
class PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final bool isShuffleEnabled;
  final RepeatMode repeatMode;
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
          icon: Icon(
            Icons.shuffle,
            color: isShuffleEnabled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).iconTheme.color,
          ),
          iconSize: 28,
          onPressed: onToggleShuffle,
          tooltip: isShuffleEnabled ? 'Shuffle: On' : 'Shuffle: Off',
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
            repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
            color: repeatMode != RepeatMode.none
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).iconTheme.color,
          ),
          iconSize: 28,
          onPressed: onToggleRepeat,
          tooltip: 'Repeat: ${repeatMode.displayName}',
        ),
      ],
    );
  }
}

/// Seek controls for forward/backward seeking
class SeekControls extends StatelessWidget {
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final Duration seekDuration;

  const SeekControls({
    super.key,
    required this.onSeekBackward,
    required this.onSeekForward,
    this.seekDuration = const Duration(seconds: 10),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.replay_10),
          onPressed: onSeekBackward,
          tooltip: 'Rewind ${seekDuration.inSeconds}s',
        ),
        const SizedBox(width: 48),
        IconButton(
          icon: const Icon(Icons.forward_10),
          onPressed: onSeekForward,
          tooltip: 'Forward ${seekDuration.inSeconds}s',
        ),
      ],
    );
  }
}

/// Progress bar with seeking capability
class ProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const ProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Slider(
          value: position.inMilliseconds.toDouble(),
          max: duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
          onChanged: (value) {
            onSeek(Duration(milliseconds: value.toInt()));
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                _formatDuration(duration),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(1, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
