import 'package:flutter/material.dart';
import '../../models/api_models.dart';

/// Playlist card widget
/// Displays playlist with auto-generated mosaic or custom cover art
class PlaylistCard extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback onTap;

  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Playlist cover art
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _buildPlaylistArt(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Playlist name
          Text(
            playlist.name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Song count
          Text(
            '${playlist.songCount} song${playlist.songCount != 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Build playlist artwork
  /// For now, uses a gradient fallback
  /// TODO: In Task 7.5, implement 2x2 mosaic of album covers
  Widget _buildPlaylistArt() {
    // Generate a gradient based on playlist name for variety
    final colorIndex = playlist.name.hashCode % 5;
    final gradients = [
      [Colors.purple[400]!, Colors.purple[700]!],
      [Colors.blue[400]!, Colors.blue[700]!],
      [Colors.green[400]!, Colors.green[700]!],
      [Colors.orange[400]!, Colors.orange[700]!],
      [Colors.pink[400]!, Colors.pink[700]!],
    ];

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients[colorIndex],
        ),
      ),
      child: const Icon(
        Icons.queue_music,
        size: 48,
        color: Colors.white,
      ),
    );
  }
}

/// Create New Playlist card widget
/// Special card shown as first item in playlists section
class CreatePlaylistCard extends StatelessWidget {
  final VoidCallback onTap;

  const CreatePlaylistCard({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Create new button
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: 48,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Label
          Text(
            'Create Playlist',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
