import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/api/connection_service.dart';
import '../../services/playback_manager.dart';
import '../../services/download/download_manager.dart';
import '../../services/quality/quality_settings_service.dart';
import '../common/cached_artwork.dart';

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

    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isAvailable ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                          fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.w500,
                          color: isCurrentTrack
                              ? Theme.of(context).primaryColor
                              : (isAvailable ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7) ?? Colors.grey[600],
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
                    color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5),
                  ),
                ),
                if (isAvailable) ...[
                  const SizedBox(width: 8),
                  _buildOverflowMenu(context),
                ] else
                  const SizedBox(width: 48), // Placeholder
              ],
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

  /// Build overflow menu button
  Widget _buildOverflowMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: 20,
        color: Colors.grey[600],
      ),
      onSelected: (value) => _handleMenuAction(context, value),
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem<String>(
          value: 'play_next',
          child: Row(
            children: [
              Icon(Icons.skip_next, size: 20),
              SizedBox(width: 12),
              Text('Play Next'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'add_queue',
          child: Row(
            children: [
              Icon(Icons.queue_music, size: 20),
              SizedBox(width: 12),
              Text('Add to Queue'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'add_playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_add, size: 20),
              SizedBox(width: 12),
              Text('Add to Playlist'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'download',
          child: Row(
            children: [
              Icon(Icons.download, size: 20),
              SizedBox(width: 12),
              Text('Download'),
            ],
          ),
        ),
      ],
    );
  }

  /// Handle menu action selection
  void _handleMenuAction(BuildContext context, String action) {
    final playbackManager = PlaybackManager();

    // Convert SongModel to Song object
    final song = Song(
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
    );

    switch (action) {
      case 'play_next':
        playbackManager.playNext(song);
        break;
      case 'add_queue':
        playbackManager.addToQueue(song);
        break;
      case 'add_playlist':
        AddToPlaylistScreen.showForSong(
          context,
          track.id,
          albumId: track.albumId,
          title: track.title,
          artist: track.artist,
          duration: track.duration,
        );
        return;
      case 'download':
        _handleDownload(context);
        return;
      default:
        return;
    }
  }

  /// Handle download action
  void _handleDownload(BuildContext context) {
    final connectionService = ConnectionService();
    final downloadManager = DownloadManager();
    final qualityService = QualitySettingsService();

    // Check if connected to server
    if (connectionService.apiClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to server')),
      );
      return;
    }

    // Construct download URL with user's download mode/quality
    final baseDownloadUrl = connectionService.apiClient!.getDownloadUrl(track.id);
    final downloadUrl = qualityService.getDownloadUrlWithQuality(baseDownloadUrl);

    downloadManager.downloadSong(
      songId: track.id,
      title: track.title,
      artist: track.artist,
      albumId: track.albumId,
      albumName: albumName,
      albumArtist: albumArtist,
      albumArt: '',
      downloadUrl: downloadUrl,
      duration: track.duration,
      trackNumber: track.trackNumber,
      totalBytes: 0, // Will be determined during download
    );
  }

  /// Format duration in seconds to mm:ss
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
