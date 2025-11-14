import 'package:flutter/material.dart';
import '../models/song.dart';
import '../models/repeat_mode.dart';
import '../widgets/player/playback_controls.dart';

/// Full player screen that slides up from mini player
class FullPlayerScreen extends StatelessWidget {
  final Song? currentSong;
  final bool isPlaying;
  final bool isLoading;
  final bool isShuffleEnabled;
  final RepeatMode repeatMode;
  final bool hasNext;
  final bool hasPrevious;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipNext;
  final VoidCallback onSkipPrevious;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onOpenQueue;

  const FullPlayerScreen({
    super.key,
    required this.currentSong,
    required this.isPlaying,
    required this.isLoading,
    required this.isShuffleEnabled,
    required this.repeatMode,
    required this.hasNext,
    required this.hasPrevious,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onSkipNext,
    required this.onSkipPrevious,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
    required this.onSeek,
    this.onOpenQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        actions: [
          if (onOpenQueue != null)
            IconButton(
              icon: const Icon(Icons.queue_music),
              onPressed: onOpenQueue,
              tooltip: 'Queue',
            ),
        ],
      ),
      body: currentSong == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_note,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No song playing',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Album artwork
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: Hero(
                          tag: 'album_art',
                          child: Container(
                            constraints: const BoxConstraints(
                              maxWidth: 400,
                              maxHeight: 400,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.music_note,
                                size: 120,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Song info
                    Expanded(
                      flex: 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            currentSong!.title,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentSong!.artist,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (currentSong!.album != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              currentSong!.album!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Progress bar
                    Expanded(
                      flex: 1,
                      child: ProgressBar(
                        position: position,
                        duration: duration,
                        onSeek: onSeek,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Playback controls
                    Expanded(
                      flex: 1,
                      child: PlaybackControls(
                        isPlaying: isPlaying,
                        isLoading: isLoading,
                        isShuffleEnabled: isShuffleEnabled,
                        repeatMode: repeatMode,
                        hasNext: hasNext,
                        hasPrevious: hasPrevious,
                        onPlayPause: onPlayPause,
                        onSkipNext: onSkipNext,
                        onSkipPrevious: onSkipPrevious,
                        onToggleShuffle: onToggleShuffle,
                        onToggleRepeat: onToggleRepeat,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
