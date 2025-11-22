import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/api/connection_service.dart';

/// Search result item for songs
class SearchResultSongItem extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;
  final String? searchQuery;

  const SearchResultSongItem({
    super.key,
    required this.song,
    required this.onTap,
    this.searchQuery,
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
      ],
    );
  }

  /// Handle menu action selection
  void _handleMenuAction(BuildContext context, String action) {
    String message;
    switch (action) {
      case 'play_next':
        message = 'Added "${song.title}" to play next';
        // TODO: Integrate with playback queue
        break;
      case 'add_queue':
        message = 'Added "${song.title}" to queue';
        // TODO: Integrate with playback queue
        break;
      case 'add_playlist':
        AddToPlaylistScreen.showForSong(context, song.id, albumId: song.albumId);
        return; // Don't show snackbar
      default:
        return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Build album artwork or placeholder
  Widget _buildAlbumArt(BuildContext context) {
    final connectionService = ConnectionService();

    // If song has an albumId, try to show album artwork
    if (song.albumId != null && connectionService.apiClient != null) {
      final artworkUrl = '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}';

      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Image.network(
            artworkUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildPlaceholder(context);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildPlaceholder(context);
            },
          ),
        ),
      );
    }

    // No album art available
    return _buildPlaceholder(context);
  }

  /// Build placeholder circle avatar
  Widget _buildPlaceholder(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
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
