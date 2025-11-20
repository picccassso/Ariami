import 'package:flutter/material.dart';
import '../services/playback_manager.dart';
import '../widgets/player/player_top_bar.dart';
import '../widgets/player/player_artwork.dart';
import '../widgets/player/player_info.dart';
import '../widgets/player/player_seek_bar.dart';
import '../widgets/player/player_secondary_controls.dart';

/// Full-screen immersive player with gestures and complete controls
/// Implements Phase 7.4 specification
class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  final PlaybackManager _playbackManager = PlaybackManager();
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    // Listen to playback state changes
    _playbackManager.addListener(_onPlaybackStateChanged);
  }

  @override
  void dispose() {
    _playbackManager.removeListener(_onPlaybackStateChanged);
    super.dispose();
  }

  void _onPlaybackStateChanged() {
    // Rebuild when playback state changes
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _playbackManager.currentSong == null ? _buildEmptyState() : _buildPlayer(),
    );
  }

  /// Build empty state when no song is playing
  Widget _buildEmptyState() {
    return SafeArea(
      child: Column(
        children: [
          // Top bar (still show minimize button)
          PlayerTopBar(
            onMinimize: () => Navigator.pop(context),
            onOpenQueue: null, // TODO: Implement queue screen
          ),
          // Empty state message
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_note,
                    size: 100,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No song playing',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build full player interface
  Widget _buildPlayer() {
    return GestureDetector(
      // Swipe down to minimize
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity! > 0) {
          // Swiped down
          Navigator.pop(context);
        }
      },
      child: SafeArea(
        child: Column(
          children: [
            // Top Bar - Minimize arrow, "Now Playing", overflow menu
            PlayerTopBar(
              onMinimize: () => Navigator.pop(context),
              onOpenQueue: null, // TODO: Implement queue screen
            ),

            const SizedBox(height: 16),

            // Album Artwork - Large, centered, with swipe gestures
            Expanded(
              flex: 4,
              child: PlayerArtwork(
                song: _playbackManager.currentSong!,
                onSwipeLeft: _playbackManager.hasNext ? _playbackManager.skipNext : () {},
                onSwipeRight: _playbackManager.hasPrevious ? _playbackManager.skipPrevious : () {},
              ),
            ),

            const SizedBox(height: 24),

            // Song Info - Title, artist, album, favorite button
            PlayerInfo(
              song: _playbackManager.currentSong!,
              isFavorite: _isFavorite,
              onToggleFavorite: () {
                setState(() {
                  _isFavorite = !_isFavorite;
                });
                // TODO: Persist favorite state (future feature)
              },
            ),

            const SizedBox(height: 24),

            // Seek Bar - Position, seekable progress, duration
            PlayerSeekBar(
              position: _playbackManager.position,
              duration: _playbackManager.duration ?? Duration.zero,
              onSeek: _playbackManager.seek,
            ),

            const SizedBox(height: 24),

            // Main Controls - Previous, Play/Pause (large), Next
            _buildMainControls(),

            const SizedBox(height: 16),

            // Secondary Controls - Shuffle, Repeat, Queue, Add to Playlist
            PlayerSecondaryControls(
              isShuffleEnabled: _playbackManager.isShuffleEnabled,
              repeatMode: _playbackManager.repeatMode,
              onToggleShuffle: _playbackManager.toggleShuffle,
              onToggleRepeat: _playbackManager.toggleRepeat,
              onOpenQueue: null, // TODO: Implement queue screen
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Build main playback controls (Previous, Play/Pause, Next)
  Widget _buildMainControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Previous button
          IconButton(
            icon: const Icon(Icons.skip_previous),
            iconSize: 48,
            onPressed: _playbackManager.hasPrevious ? _playbackManager.skipPrevious : null,
            tooltip: 'Previous',
          ),

          // Play/Pause button (large, prominent)
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _playbackManager.isLoading
                ? Center(
                    child: SizedBox(
                      width: 36,
                      height: 36,
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
                      _playbackManager.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    iconSize: 40,
                    onPressed: _playbackManager.togglePlayPause,
                    tooltip: _playbackManager.isPlaying ? 'Pause' : 'Play',
                  ),
          ),

          // Next button
          IconButton(
            icon: const Icon(Icons.skip_next),
            iconSize: 48,
            onPressed: _playbackManager.hasNext ? _playbackManager.skipNext : null,
            tooltip: 'Next',
          ),
        ],
      ),
    );
  }
}
