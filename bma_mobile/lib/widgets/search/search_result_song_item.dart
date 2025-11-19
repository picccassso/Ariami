import 'package:flutter/material.dart';
import '../../models/api_models.dart';
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
      trailing: Text(
        _formatDuration(song.duration),
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[600],
        ),
      ),
      onTap: onTap,
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
