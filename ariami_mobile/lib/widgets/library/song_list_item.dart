import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/playback_manager.dart';
import '../../services/download/download_manager.dart';
import '../../services/api/connection_service.dart';
import '../../services/quality/quality_settings_service.dart';
import '../common/cached_artwork.dart';

/// Song list item widget
/// Displays song title, artist, and duration in a list row
class SongListItem extends StatelessWidget {
  final SongModel song;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isDownloaded;
  final bool isCached;
  final bool isAvailable;
  final String? albumName;
  final String? albumArtist;

  const SongListItem({
    super.key,
    required this.song,
    this.onTap,
    this.onLongPress,
    this.isDownloaded = false,
    this.isCached = false,
    this.isAvailable = true,
    this.albumName,
    this.albumArtist,
  });

  @override
  Widget build(BuildContext context) {
    // Apply opacity when song is not available (offline and not downloaded)
    final opacity = isAvailable ? 1.0 : 0.5;

    return Opacity(
      opacity: opacity,
      child: ListTile(
        onTap: isAvailable ? onTap : null,
        onLongPress: onLongPress,
        leading: _buildLeading(context),
        title: Text(
          song.title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isAvailable ? null : Colors.grey,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          song.artist,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDuration(song.duration),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showSongMenu(context),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  /// Build leading widget with artwork and download/cache indicator
  Widget _buildLeading(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
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
      ),
    );
  }

  /// Build album artwork or placeholder using CachedArtwork
  Widget _buildAlbumArt(BuildContext context) {
    final connectionService = ConnectionService();

    // Determine artwork URL based on whether song has albumId
    String? artworkUrl;
    String cacheId;

    if (song.albumId != null) {
      // Song belongs to an album - use album artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}'
          : null;
      cacheId = song.albumId!;
    } else {
      // Standalone song - use song artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${song.id}'
          : null;
      cacheId = 'song_${song.id}'; // Prefix to differentiate from album IDs
    }

    // Force square aspect ratio to ensure BoxFit.cover crops bars completely
    return AspectRatio(
      aspectRatio: 1.0,
      child: CachedArtwork(
        albumId: cacheId, // Used as cache key
        artworkUrl: artworkUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(4),
        fallback: _buildPlaceholder(),
        fallbackIcon: Icons.music_note,
        fallbackIconSize: 24,
      ),
    );
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

  /// Format duration in seconds to mm:ss
  String _formatDuration(int durationInSeconds) {
    final minutes = durationInSeconds ~/ 60;
    final seconds = durationInSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Show song overflow menu
  void _showSongMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          minimum: EdgeInsets.only(
            bottom: 64 + kBottomNavigationBarHeight, // Mini player + download bar + nav bar
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                title: const Text('Add to Queue'),
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
                leading: const Icon(Icons.download),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(context);
                  _handleDownload(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Handle play next action
  void _handlePlayNext(BuildContext context) {
    final playbackManager = PlaybackManager();

    // Convert SongModel to Song object
    final convertedSong = Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: null,
      albumId: song.albumId,
      duration: Duration(seconds: song.duration),
      filePath: song.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: song.trackNumber,
    );

    playbackManager.playNext(convertedSong);
  }

  /// Handle add to queue action
  void _handleAddToQueue(BuildContext context) {
    final playbackManager = PlaybackManager();

    // Convert SongModel to Song object
    final convertedSong = Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: null,
      albumId: song.albumId,
      duration: Duration(seconds: song.duration),
      filePath: song.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: song.trackNumber,
    );

    playbackManager.addToQueue(convertedSong);
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

    // Construct download URL with user's preferred download quality
    final downloadQuality = qualityService.getDownloadQuality();
    final downloadUrl = connectionService.apiClient!.getDownloadUrlWithQuality(
      song.id,
      downloadQuality,
    );

    downloadManager.downloadSong(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      albumId: song.albumId,
      albumName: albumName,
      albumArtist: albumArtist,
      albumArt: '',
      downloadUrl: downloadUrl,
      duration: song.duration,
      trackNumber: song.trackNumber,
      totalBytes: 0, // Will be determined during download
    );
  }
}
