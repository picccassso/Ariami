import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../services/api/connection_service.dart';
import '../../services/playback_manager.dart';
import '../common/cached_artwork.dart';
import '../common/song_overflow_menu.dart';
import '../common/swipe_to_queue.dart';

/// Track list item for album detail view
/// Shows album artwork, title, duration, and overflow menu
class TrackListItem extends StatelessWidget {
  final SongModel track;
  final VoidCallback? onTap;
  final bool isCurrentTrack;
  final bool isDownloaded;
  final bool isCached;
  final bool isAvailable;
  final String? albumName;
  final String? albumArtist;

  const TrackListItem({
    super.key,
    required this.track,
    this.onTap,
    this.isCurrentTrack = false,
    this.isDownloaded = false,
    this.isCached = false,
    this.isAvailable = true,
    this.albumName,
    this.albumArtist,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = isAvailable ? 1.0 : 0.4;

    return SwipeToQueue(
      itemKey: ValueKey('album_queue_${track.id}'),
      addToQueueEnabled: isAvailable,
      onAddToQueue: _addTrackToQueue,
      child: Opacity(
        opacity: opacity,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAvailable ? onTap : null,
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
                      mainAxisSize: MainAxisSize.min, // shrink wrap
                      children: [
                        Text(
                          track.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isCurrentTrack
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isCurrentTrack
                                ? Theme.of(context).primaryColor
                                : (isAvailable
                                    ? Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color
                                    : Colors.grey),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artist,
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
                    _formatDuration(track.duration),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.5),
                    ),
                  ),
                  if (isAvailable) ...[
                    const SizedBox(width: 8),
                    SongOverflowMenu(
                      song: track,
                      onPlay: onTap,
                      isDownloaded: isDownloaded,
                      albumName: albumName,
                      albumArtist: albumArtist,
                    ),
                  ] else
                    const SizedBox(width: 48), // Placeholder
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build leading widget with download/cache indicator
  Widget _buildLeading(BuildContext context) {
    return Stack(
      children: [
        _buildAlbumArt(context),
        if (isDownloaded)
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
        else if (isCached)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.blue[400],
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
    );
  }

  /// Build album artwork or placeholder using CachedArtwork
  Widget _buildAlbumArt(BuildContext context) {
    final connectionService = ConnectionService();

    if (track.albumId != null) {
      final artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${track.albumId}'
          : null;

      return CachedArtwork(
        albumId: track.albumId!,
        artworkUrl: artworkUrl,
        width: 48,
        height: 48,
        borderRadius: BorderRadius.circular(4),
        fallback: _buildPlaceholder(),
        fallbackIcon: Icons.music_note,
        fallbackIconSize: 24,
        sizeHint: ArtworkSizeHint.thumbnail,
      );
    }

    return _buildPlaceholder();
  }

  /// Build placeholder for missing artwork
  Widget _buildPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.music_note, color: Colors.grey),
    );
  }

  void _addTrackToQueue() {
    PlaybackManager().addToQueue(
      Song(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: null,
        albumId: track.albumId,
        duration: Duration(seconds: track.duration),
        filePath: track.id,
        fileSize: 0,
        modifiedTime: DateTime.now(),
        trackNumber: track.trackNumber,
      ),
    );
  }

  /// Format duration in seconds to mm:ss
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
