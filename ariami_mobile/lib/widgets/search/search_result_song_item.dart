import 'package:flutter/material.dart';
import 'package:ariami_core/utils/format.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../utils/song_from_model.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../utils/artwork_url.dart';
import '../../services/playback_manager.dart';
import '../common/cached_artwork.dart';
import '../common/lyrics_badge.dart';
import '../common/mini_player_aware_bottom_sheet.dart';
import '../common/playing_bars.dart';
import '../common/song_artwork.dart';
import '../common/song_overflow_menu.dart';
import '../common/swipe_to_queue.dart';

class SearchResultSongItem extends StatefulWidget {
  final SongModel song;
  final VoidCallback onTap;
  final String? searchQuery;
  final String? albumName;
  final String? albumArtist;
  final bool isDownloaded;
  final bool isCached;
  final bool isAvailable;
  final VoidCallback? onRemove;
  final bool showRemoveFromRecent;
  final bool isInRecentSearch;

  const SearchResultSongItem({
    super.key,
    required this.song,
    required this.onTap,
    this.searchQuery,
    this.albumName,
    this.albumArtist,
    this.isDownloaded = false,
    this.isCached = false,
    this.isAvailable = true,
    this.onRemove,
    this.showRemoveFromRecent = false,
    this.isInRecentSearch = false,
  });

  @override
  State<SearchResultSongItem> createState() => _SearchResultSongItemState();
}

class _SearchResultSongItemState extends State<SearchResultSongItem> {
  static const double _kSwipeEdgeGuard = 24.0;
  bool _dismissSwipeArmed = true;

  void _armDismissSwipe(PointerDownEvent event, double itemWidth) {
    final startX = event.localPosition.dx;
    final isInsideSafeZone =
        startX >= _kSwipeEdgeGuard && startX <= itemWidth - _kSwipeEdgeGuard;

    if (_dismissSwipeArmed != isInsideSafeZone) {
      setState(() {
        _dismissSwipeArmed = isInsideSafeZone;
      });
    }
  }

  void _resetDismissSwipe() {
    if (_dismissSwipeArmed) {
      return;
    }
    setState(() {
      _dismissSwipeArmed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Apply opacity when song is not available (offline and not downloaded)
    final opacity = widget.isAvailable ? 1.0 : 0.5;
    final playbackManager = PlaybackManager();

    return ListenableBuilder(
      listenable: playbackManager,
      builder: (context, _) {
        final isCurrent = widget.isAvailable &&
            playbackManager.currentSong?.id == widget.song.id;
        final isAnimating =
            isCurrent && (playbackManager.isPlaying || playbackManager.isLoading);

        final titleColor = !widget.isAvailable
            ? Colors.grey
            : (isCurrent
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).textTheme.bodyLarge?.color);

        final content = Opacity(
          opacity: opacity,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isAvailable ? widget.onTap : null,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    _buildLeading(context),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.song.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: titleColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.song.hasLyrics) ...[
                                const SizedBox(width: 6),
                                const LyricsBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.song.artist,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withValues(alpha: 0.7) ??
                                  Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      formatMinSec(widget.song.duration),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.5),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      PlayingBars(
                        playing: isAnimating,
                        color: Theme.of(context).colorScheme.primary,
                        size: 16,
                      ),
                    ],
                    if (widget.isAvailable) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                        onPressed: () => _showSongMenu(context),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 40, minHeight: 40),
                      ),
                    ] else
                      const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),
        );

        if (widget.onRemove != null) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth;

              return Listener(
                onPointerDown: (event) => _armDismissSwipe(event, itemWidth),
                onPointerUp: (_) => _resetDismissSwipe(),
                onPointerCancel: (_) => _resetDismissSwipe(),
                child: SwipeToQueue(
                  itemKey: ValueKey('search_queue_${widget.song.id}'),
                  addToQueueEnabled: widget.isAvailable,
                  onAddToQueue: _handleAddToQueue,
                  onRemove: _dismissSwipeArmed ? widget.onRemove : null,
                  child: content,
                ),
              );
            },
          );
        }

        return SwipeToQueue(
          itemKey: ValueKey('search_queue_${widget.song.id}'),
          addToQueueEnabled: widget.isAvailable,
          onAddToQueue: _handleAddToQueue,
          child: content,
        );
      },
    );
  }

  void _showSongMenu(BuildContext context) {
    showAriamiSheet<void>(
      context: context,
      header: AriamiSheetHeader(
        title: widget.song.title,
        subtitle: widget.song.artist,
        leading: SongArtwork(song: widget.song),
      ),
      items: [
        ListTile(
          leading: const Icon(Icons.play_arrow),
          title: const Text('Play'),
          onTap: () {
            Navigator.pop(context);
            widget.onTap();
          },
        ),
        SongLikeMenuItem(song: widget.song),
        ListTile(
          leading: const Icon(Icons.skip_next),
          title: const Text('Play Next'),
          onTap: () {
            Navigator.pop(context);
            _handlePlayNext();
          },
        ),
        ListTile(
          leading: const Icon(Icons.queue_music),
          title: const Text('Add to End of Queue'),
          onTap: () {
            Navigator.pop(context);
            _handleAddToQueue();
          },
        ),
        ListTile(
          leading: const Icon(Icons.playlist_add),
          title: const Text('Add to Playlist'),
          onTap: () {
            Navigator.pop(context);
            AddToPlaylistScreen.showForSong(
              context,
              widget.song.id,
              albumId: widget.song.albumId,
              title: widget.song.title,
              artist: widget.song.artist,
              duration: widget.song.duration,
            );
          },
        ),
        if (widget.song.albumId != null)
          ListTile(
            leading: const Icon(Icons.album_outlined),
            title: const Text('Show in album'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushNamed(
                '/album',
                arguments: AlbumModel(
                  id: widget.song.albumId!,
                  title: widget.albumName ?? 'Unknown Album',
                  artist: widget.albumArtist ?? widget.song.artist,
                  songCount: 0,
                  duration: 0,
                ),
              );
            },
          ),
        if (widget.showRemoveFromRecent && widget.onRemove != null)
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Remove from Recent',
                style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              widget.onRemove!();
            },
          ),
      ],
    );
  }

  Song _toSong() => songFromModel(widget.song);

  void _handlePlayNext() {
    final playbackManager = PlaybackManager();
    playbackManager.playNext(_toSong());
  }

  void _handleAddToQueue() {
    final playbackManager = PlaybackManager();
    playbackManager.addToQueue(_toSong());
  }

  Widget _buildLeading(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          _buildAlbumArt(context),
          if (widget.isInRecentSearch)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: 10,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          if (widget.isDownloaded)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.green[600],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.download_done,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            )
          else if (widget.isCached)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_done,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(BuildContext context) {
    final artwork = resolveSongArtwork(
        songId: widget.song.id, albumId: widget.song.albumId);

    return CachedArtwork(
      albumId: artwork.cacheId,
      artworkUrl: artwork.url,
      width: 48,
      height: 48,
      borderRadius: BorderRadius.circular(4),
      fallback: _buildPlaceholder(context),
      fallbackIcon: Icons.music_note,
      fallbackIconSize: 24,
      sizeHint: ArtworkSizeHint.thumbnail,
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.music_note,
        color: Theme.of(context).primaryColor,
      ),
    );
  }
}
