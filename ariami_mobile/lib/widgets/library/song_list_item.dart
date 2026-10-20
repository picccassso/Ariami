import 'package:flutter/material.dart';
import 'package:ariami_core/utils/format.dart';
import '../../utils/artwork_url.dart';
import '../common/mini_player_aware_bottom_sheet.dart';
import '../../models/api_models.dart';
import '../../utils/song_from_model.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/playback_manager.dart';
import '../../services/download/download_manager.dart';
import '../../services/api/connection_service.dart';
import '../common/artist_link.dart';
import '../common/cached_artwork.dart';
import '../common/track_badge.dart';
import '../common/song_artwork.dart';
import '../common/song_overflow_menu.dart';
import '../common/swipe_to_queue.dart';

class SongListItem extends StatelessWidget {
  final SongModel song;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isDownloaded;
  final bool isCached;
  final bool isAvailable;
  final bool isOfflineCopy;
  final String? albumName;
  final String? albumArtist;
  final bool isSelectionMode;
  final bool isSelected;

  /// Whether the artist name links to the artist page. Disable on screens
  /// whose navigator has no `/artist` route.
  final bool artistLinkEnabled;

  const SongListItem({
    super.key,
    required this.song,
    this.onTap,
    this.onLongPress,
    this.isDownloaded = false,
    this.isCached = false,
    this.isAvailable = true,
    this.isOfflineCopy = false,
    this.albumName,
    this.albumArtist,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.artistLinkEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = isAvailable ? 1.0 : 0.5;

    return SwipeToQueue(
      itemKey: ValueKey('library_queue_${song.id}'),
      addToQueueEnabled: isAvailable && !isSelectionMode,
      onAddToQueue: () => _handleAddToQueue(context),
      child: Opacity(
        opacity: opacity,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAvailable ? onTap : null,
            onLongPress: isSelectionMode ? null : onLongPress,
            borderRadius: BorderRadius.circular(0),
            child: Container(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.transparent,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    if (isSelectionMode) ...[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                size: 14,
                                color: Theme.of(context).colorScheme.onPrimary,
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                    ],
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
                                  song.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: isAvailable
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                            : Colors.grey,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TrackBadge(
                                hasLyrics: song.hasLyrics,
                                isInstrumental: song.isInstrumental,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: ArtistLink(
                                  name: song.artist,
                                  enabled:
                                      artistLinkEnabled && !isSelectionMode,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontSize: 14,
                                        color: isOfflineCopy
                                            ? Theme.of(context)
                                                .colorScheme
                                                .secondary
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.6),
                                      ),
                                ),
                              ),
                              if (isOfflineCopy)
                                Text(
                                  ' · Offline copy',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontSize: 14,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondary,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatMinSec(song.duration),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.4),
                                  ),
                        ),
                        if (!isSelectionMode) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                              size: 20,
                            ),
                            onPressed: () => _showSongMenu(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 40, minHeight: 40),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    return Container(
      width: 56, // Larger size
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(0), // Smoother corners
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(0),
            child: _buildAlbumArt(context),
          ),
          if (isDownloaded)
            Positioned(
              bottom: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isOfflineCopy
                      ? Theme.of(context).colorScheme.secondary
                      : Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2),
                ),
                child: Icon(
                  isOfflineCopy ? Icons.cloud_off_rounded : Icons.check,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            )
          else if (isCached)
            Positioned(
              bottom: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2),
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
    final artwork = resolveSongArtwork(songId: song.id, albumId: song.albumId);

    // Force square aspect ratio to ensure BoxFit.cover crops bars completely
    return AspectRatio(
      aspectRatio: 1.0,
      child: CachedArtwork(
        albumId: artwork.cacheId, // Used as cache key
        artworkUrl: artwork.url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(0),
        fallback: _buildPlaceholder(),
        fallbackIcon: Icons.music_note,
        fallbackIconSize: 24,
        sizeHint: ArtworkSizeHint.thumbnail,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(0),
      ),
      child: const Icon(Icons.music_note, color: Colors.grey),
    );
  }

  void _showSongMenu(BuildContext context) {
    showAriamiSheet<void>(
      context: context,
      header: AriamiSheetHeader(
        title: song.title,
        subtitle: song.artist,
        leading: SongArtwork(song: song),
      ),
      items: [
        ListTile(
          leading: const Icon(Icons.play_arrow),
          title: const Text('Play'),
          onTap: onTap != null
              ? () {
                  Navigator.pop(context);
                  onTap?.call();
                }
              : null,
        ),
        SongLikeMenuItem(song: song),
        ListTile(
          leading: const Icon(Icons.skip_next),
          title: const Text('Play Next'),
          onTap: () {
            Navigator.pop(context);
            _handlePlayNext(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.queue_music),
          title: const Text('Add to End of Queue'),
          onTap: () {
            Navigator.pop(context);
            _handleAddToQueue(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.playlist_add),
          title: const Text('Add to Playlist'),
          onTap: () {
            Navigator.pop(context);
            AddToPlaylistScreen.showForSong(
              context,
              song.id,
              albumId: song.albumId,
              title: song.title,
              artist: song.artist,
              duration: song.duration,
            );
          },
        ),
        ListTile(
          leading: Icon(
            isDownloaded ? Icons.download_done : Icons.download,
            color: isDownloaded ? Colors.green : null,
          ),
          title: Text(isDownloaded ? 'Downloaded' : 'Download'),
          onTap: isDownloaded
              ? null
              : () {
                  Navigator.pop(context);
                  _handleDownload(context);
                },
        ),
      ],
    );
  }

  void _handlePlayNext(BuildContext context) {
    final playbackManager = PlaybackManager();

    playbackManager.playNext(songFromModel(song));
  }

  void _handleAddToQueue(BuildContext context) {
    final playbackManager = PlaybackManager();

    playbackManager.addToQueue(songFromModel(song));
  }

  void _handleDownload(BuildContext context) {
    if (isDownloaded) {
      return;
    }

    final connectionService = ConnectionService();
    final downloadManager = DownloadManager();

    if (connectionService.apiClient == null) {
      return;
    }

    downloadManager.downloadSong(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      albumId: song.albumId,
      albumName: albumName,
      albumArtist: albumArtist,
      albumArt: '',
      duration: song.duration,
      trackNumber: song.trackNumber,
      totalBytes: 0, // Will be determined during download
    );
  }
}
