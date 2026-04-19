import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/api/connection_service.dart';
import '../../services/playback_manager.dart';
import '../common/cached_artwork.dart';
import '../common/mini_player_aware_bottom_sheet.dart';

/// Search result item for songs with optional swipe-to-delete and remove from recent
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
  });

  @override
  State<SearchResultSongItem> createState() => _SearchResultSongItemState();
}

class _SearchResultSongItemState extends State<SearchResultSongItem> {
  static const double _kSwipeEdgeGuard = 24.0;
  static const double _kRemoveDismissThreshold = 0.6;
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

    final content = Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isAvailable ? widget.onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                _buildLeading(context),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.song.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: widget.isAvailable ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                  _formatDuration(widget.song.duration),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withValues(alpha: 0.5),
                  ),
                ),
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

    // Wrap with Dismissible if onRemove callback is provided
    if (widget.onRemove != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth;

          return Listener(
            onPointerDown: (event) => _armDismissSwipe(event, itemWidth),
            onPointerUp: (_) => _resetDismissSwipe(),
            onPointerCancel: (_) => _resetDismissSwipe(),
            child: Dismissible(
              key: ValueKey('dismiss_${widget.song.id}'),
              direction: _dismissSwipeArmed
                  ? DismissDirection.endToStart
                  : DismissDirection.none,
              dismissThresholds: const <DismissDirection, double>{
                DismissDirection.endToStart: _kRemoveDismissThreshold,
              },
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (direction) async {
                return _dismissSwipeArmed &&
                    direction == DismissDirection.endToStart;
              },
              onDismissed: (_) => widget.onRemove?.call(),
              child: content,
            ),
          );
        },
      );
    }

    return content;
  }

  /// Show song overflow menu
  void _showSongMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        final maxMenuHeight = MediaQuery.sizeOf(context).height * 0.9;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxMenuHeight),
          child: SafeArea(
            minimum: EdgeInsets.only(
              bottom: getMiniPlayerAwareBottomPadding(context),
            ),
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.play_arrow),
                      title: const Text('Play'),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onTap();
                      },
                    ),
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
                      title: const Text('Add to Queue'),
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
                    if (widget.showRemoveFromRecent && widget.onRemove != null)
                      ListTile(
                        leading: const Icon(Icons.delete_outline, color: Colors.red),
                        title: const Text('Remove from Recent', style: TextStyle(color: Colors.red)),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onRemove!();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Song _toSong() {
    return Song(
      id: widget.song.id,
      title: widget.song.title,
      artist: widget.song.artist,
      album: null,
      albumId: widget.song.albumId,
      duration: Duration(seconds: widget.song.duration),
      filePath: widget.song.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: widget.song.trackNumber,
    );
  }

  void _handlePlayNext() {
    final playbackManager = PlaybackManager();
    playbackManager.playNext(_toSong());
  }

  void _handleAddToQueue() {
    final playbackManager = PlaybackManager();
    playbackManager.addToQueue(_toSong());
  }

  /// Build leading widget with artwork and download/cache indicator
  Widget _buildLeading(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          _buildAlbumArt(context),
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

  /// Build album artwork or placeholder using CachedArtwork
  Widget _buildAlbumArt(BuildContext context) {
    final connectionService = ConnectionService();

    // Determine artwork URL based on whether song has albumId
    String? artworkUrl;
    String cacheId;

    if (widget.song.albumId != null) {
      // Song belongs to an album - use album artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${widget.song.albumId}'
          : null;
      cacheId = widget.song.albumId!;
    } else {
      // Standalone song - use song artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${widget.song.id}'
          : null;
      cacheId = 'song_${widget.song.id}';
    }

    return CachedArtwork(
      albumId: cacheId,
      artworkUrl: artworkUrl,
      width: 48,
      height: 48,
      borderRadius: BorderRadius.circular(4),
      fallback: _buildPlaceholder(context),
      fallbackIcon: Icons.music_note,
      fallbackIconSize: 24,
      sizeHint: ArtworkSizeHint.thumbnail,
    );
  }

  /// Build placeholder circle avatar
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

  /// Format duration in seconds to mm:ss
  String _formatDuration(int durationInSeconds) {
    final minutes = durationInSeconds ~/ 60;
    final seconds = durationInSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
