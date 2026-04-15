import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/playback_manager.dart';
import '../services/playlist_service.dart';
import '../services/color_extraction_service.dart';
import '../utils/constants.dart';
import '../models/repeat_mode.dart' as playback_repeat;
import '../widgets/player/player_top_bar.dart';
import '../widgets/player/player_artwork.dart';
import '../widgets/player/player_info.dart';
import '../widgets/player/player_seek_bar.dart';
import '../widgets/player/player_secondary_controls.dart';
import '../widgets/player/player_cast_button.dart';
import 'playlist/add_to_playlist_screen.dart';
import 'queue_screen.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  final PlaybackManager _playbackManager = PlaybackManager();
  final PlaylistService _playlistService = PlaylistService();
  final ColorExtractionService _colorService = ColorExtractionService();

  @override
  void initState() {
    super.initState();
    _playbackManager.addListener(_onPlaybackStateChanged);
    _playlistService.loadPlaylists();
    _playlistService.addListener(_onPlaylistsChanged);
    _colorService.addListener(_onColorsChanged);
    if (_playbackManager.currentSong != null) {
      _colorService.extractColorsForSong(_playbackManager.currentSong);
    }
  }

  @override
  void dispose() {
    _playbackManager.removeListener(_onPlaybackStateChanged);
    _playlistService.removeListener(_onPlaylistsChanged);
    _colorService.removeListener(_onColorsChanged);
    super.dispose();
  }

  void _onColorsChanged() {
    setState(() {});
  }

  void _onPlaybackStateChanged() {
    setState(() {});
  }

  void _onPlaylistsChanged() {
    setState(() {});
  }

  /// Check if current song is liked
  bool get _isFavorite {
    final currentSong = _playbackManager.currentSong;
    if (currentSong == null) return false;
    return _playlistService.isLikedSong(currentSong.id);
  }

  void _openQueue() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QueueScreen(
          queue: _playbackManager.queue,
          onReorder: (oldIndex, newIndex) {
            _playbackManager.reorderQueueFromDisplayOrder(oldIndex, newIndex);
          },
          onTap: (index) {
            _playbackManager.queue.jumpToIndex(index);
          },
          onRemove: (index) {
            _playbackManager.queue.removeSong(index);
          },
          onClear: _playbackManager.queue.clear,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colorService.currentColors;
    final useDarkStatusIcons = colors.primary.computeLuminance() > 0.55;
    final overlayStyle = (useDarkStatusIcons
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light)
        .copyWith(statusBarColor: Colors.transparent);

    return Theme(
      data: AppTheme.buildTheme(
        brightness: Brightness.dark,
        seedColor: colors.primary,
      ),
      child: Builder(
        builder: (themedContext) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: Scaffold(
              body: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.5,
                    colors: [
                      colors.primary.withValues(alpha: 0.85),
                      colors.secondary.withValues(alpha: 0.65),
                      Colors.black,
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
                child: _playbackManager.currentSong == null
                    ? _buildEmptyState(themedContext)
                    : _buildPlayer(themedContext),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext themedContext) {
    return SafeArea(
      child: Column(
        children: [
          PlayerTopBar(
            onMinimize: () => Navigator.pop(context),
            onOpenQueue: _openQueue,
            castButton: PlayerCastButton(playbackManager: _playbackManager),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.music,
                    size: 100,
                    color: Theme.of(themedContext).colorScheme.outline,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No song playing',
                    style: Theme.of(themedContext)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                          color: Theme.of(themedContext).colorScheme.outline,
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

  Widget _buildPlayer(BuildContext themedContext) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity! > 0) {
          Navigator.pop(context);
        }
      },
      child: SafeArea(
        child: Column(
          children: [
            PlayerTopBar(
              onMinimize: () => Navigator.pop(context),
              onOpenQueue: _openQueue,
              castButton: PlayerCastButton(playbackManager: _playbackManager),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 4,
              child: PlayerArtwork(
                queue: _playbackManager.queue,
                currentIndex: _playbackManager.queue.currentIndex,
                onPageChanged: (index) {
                  _playbackManager.skipToQueueItem(index);
                },
              ),
            ),
            const SizedBox(height: 24),
            PlayerInfo(
              song: _playbackManager.currentSong!,
              isFavorite: _isFavorite,
              onToggleFavorite: () async {
                final song = _playbackManager.currentSong;
                if (song != null) {
                  await _playlistService.toggleLikedSong(
                    song.id,
                    song.albumId,
                    title: song.title,
                    artist: song.artist,
                    duration: song.duration.inSeconds,
                  );
                }
              },
            ),
            const SizedBox(height: 24),
            PlayerSeekBar(
              position: _playbackManager.position,
              duration: _playbackManager.duration ?? Duration.zero,
              onSeek: _playbackManager.seek,
            ),
            const SizedBox(height: 24),
            _buildMainControls(themedContext),
            const SizedBox(height: 16),
            PlayerSecondaryControls(
              onOpenQueue: _openQueue,
              onAddToPlaylist: () {
                final song = _playbackManager.currentSong;
                if (song != null) {
                  AddToPlaylistScreen.showForSong(
                    context,
                    song.id,
                    albumId: song.albumId,
                    title: song.title,
                    artist: song.artist,
                    duration: song.duration.inSeconds,
                  );
                }
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Build main playback controls (Shuffle, Previous, Play/Pause, Next, Repeat)
  Widget _buildMainControls(BuildContext themedContext) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Shuffle button
          IconButton(
            icon: const Icon(Icons.shuffle_rounded),
            onPressed: _playbackManager.toggleShuffle,
            tooltip: _playbackManager.isShuffleEnabled
                ? 'Shuffle on'
                : 'Shuffle off',
            iconSize: 28,
            color: _playbackManager.isShuffleEnabled
                ? Theme.of(themedContext).colorScheme.primary
                : Theme.of(themedContext)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.9),
          ),

          // Previous button
          IconButton(
            icon: const Icon(LucideIcons.skipBack),
            iconSize: 48,
            onPressed: _playbackManager.hasPrevious
                ? _playbackManager.skipPrevious
                : null,
            tooltip: 'Previous',
          ),

          // Play/Pause button (large, prominent)
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(themedContext).colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    themedContext,
                  ).colorScheme.primary.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _playbackManager.isLoading
                ? Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(themedContext).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  )
                : IconButton(
                    icon: Icon(
                      _playbackManager.isPlaying
                          ? LucideIcons.pause
                          : LucideIcons.play,
                      color: Theme.of(themedContext).colorScheme.onPrimary,
                    ),
                    iconSize: 42,
                    onPressed: _playbackManager.togglePlayPause,
                    tooltip: _playbackManager.isPlaying ? 'Pause' : 'Play',
                  ),
          ),

          // Next button
          IconButton(
            icon: const Icon(LucideIcons.skipForward),
            iconSize: 48,
            onPressed: (_playbackManager.hasNext ||
                    (_playbackManager.repeatMode ==
                            playback_repeat.RepeatMode.all &&
                        _playbackManager.queue.isNotEmpty))
                ? _playbackManager.skipNext
                : null,
            tooltip: 'Next',
          ),

          // Repeat button
          IconButton(
            icon: Icon(_getRepeatIcon(_playbackManager.repeatMode)),
            onPressed: _playbackManager.toggleRepeat,
            tooltip: _getRepeatTooltip(_playbackManager.repeatMode),
            iconSize: 28,
            color:
                _playbackManager.repeatMode != playback_repeat.RepeatMode.none
                    ? Theme.of(themedContext).colorScheme.primary
                    : Theme.of(themedContext)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.9),
          ),
        ],
      ),
    );
  }

  /// Get repeat mode icon
  IconData _getRepeatIcon(playback_repeat.RepeatMode mode) {
    switch (mode) {
      case playback_repeat.RepeatMode.none:
        return Icons.repeat_rounded;
      case playback_repeat.RepeatMode.all:
        return Icons.repeat_rounded;
      case playback_repeat.RepeatMode.one:
        return Icons.repeat_one_rounded;
    }
  }

  /// Get repeat mode tooltip
  String _getRepeatTooltip(playback_repeat.RepeatMode mode) {
    switch (mode) {
      case playback_repeat.RepeatMode.none:
        return 'Repeat off';
      case playback_repeat.RepeatMode.all:
        return 'Repeat all';
      case playback_repeat.RepeatMode.one:
        return 'Repeat one';
    }
  }
}
