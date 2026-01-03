import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/api/connection_service.dart';
import '../../services/playback_manager.dart';
import '../../services/download/download_manager.dart';
import '../common/cached_artwork.dart';

/// Search result item for songs
class SearchResultSongItem extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;
  final String? searchQuery;
  final String? albumName;
  final String? albumArtist;

  const SearchResultSongItem({
    super.key,
    required this.song,
    required this.onTap,
    this.searchQuery,
    this.albumName,
    this.albumArtist,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildAlbumArt(context),
      title: Text(
        song.title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
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
          _buildOverflowMenu(context),
        ],
      ),
      onTap: onTap,
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

    switch (action) {
      case 'play_next':
        playbackManager.playNext(convertedSong);
        break;
      case 'add_queue':
        playbackManager.addToQueue(convertedSong);
        break;
      case 'add_playlist':
        AddToPlaylistScreen.showForSong(
          context,
          song.id,
          albumId: song.albumId,
          title: song.title,
          artist: song.artist,
          duration: song.duration,
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

    // Check if connected to server
    if (connectionService.apiClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to server')),
      );
      return;
    }

    // Construct download URL using actual server connection
    final downloadUrl = '${connectionService.apiClient!.baseUrl}/download/${song.id}';

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
      totalBytes: 0,
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
      cacheId = 'song_${song.id}';
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
