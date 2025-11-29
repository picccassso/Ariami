import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/api/connection_service.dart';
import '../../services/playback_manager.dart';

/// Track list item for album detail view
/// Shows album artwork, title, duration, and overflow menu
class TrackListItem extends StatelessWidget {
  final SongModel track;
  final VoidCallback onTap;
  final bool isCurrentTrack;

  const TrackListItem({
    super.key,
    required this.track,
    required this.onTap,
    this.isCurrentTrack = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      tileColor: isCurrentTrack
          ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
          : null,
      leading: _buildAlbumArt(context),
      title: Text(
        track.title,
        style: TextStyle(
          fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.normal,
          color: isCurrentTrack ? Theme.of(context).primaryColor : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[600]),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatDuration(track.duration),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          _buildOverflowMenu(context),
        ],
      ),
    );
  }

  /// Build album artwork or placeholder
  Widget _buildAlbumArt(BuildContext context) {
    final connectionService = ConnectionService();

    if (track.albumId != null && connectionService.apiClient != null) {
      final artworkUrl =
          '${connectionService.apiClient!.baseUrl}/artwork/${track.albumId}';

      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Image.network(
            artworkUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildPlaceholder();
            },
          ),
        ),
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
        AddToPlaylistScreen.showForSong(context, track.id, albumId: track.albumId);
        return;
      default:
        return;
    }
  }

  /// Format duration in seconds to mm:ss
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
