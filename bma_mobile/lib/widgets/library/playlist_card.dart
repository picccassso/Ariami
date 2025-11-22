import 'package:flutter/material.dart';
import '../../models/api_models.dart';

/// Playlist card widget
/// Displays playlist with dynamic mosaic artwork based on songs
class PlaylistCard extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback onTap;

  /// List of artwork URLs for the collage (up to 4)
  final List<String> artworkUrls;

  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.artworkUrls = const [],
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Playlist cover art with fixed square aspect ratio (same as albums)
          AspectRatio(
            aspectRatio: 1.0,
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
          const SizedBox(height: 4),
          // Playlist name and count in expanded container (same as albums)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Playlist name
                Text(
                  playlist.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
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
          ),
        ],
      ),
    );
  }

  /// Build playlist artwork - collage or fallback
  Widget _buildPlaylistArt() {
    if (artworkUrls.isEmpty) {
      return _buildFallbackArt();
    }

    if (artworkUrls.length == 1) {
      // Single artwork
      return _buildArtworkImage(artworkUrls[0]);
    } else if (artworkUrls.length == 2 || artworkUrls.length == 3) {
      // Two artworks side by side
      return Row(
        children: [
          Expanded(child: _buildArtworkImage(artworkUrls[0])),
          Expanded(child: _buildArtworkImage(artworkUrls[1])),
        ],
      );
    } else {
      // Four artworks in a grid (2x2)
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildArtworkImage(artworkUrls[0])),
                Expanded(child: _buildArtworkImage(artworkUrls[1])),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildArtworkImage(artworkUrls[2])),
                Expanded(child: _buildArtworkImage(artworkUrls[3])),
              ],
            ),
          ),
        ],
      );
    }
  }

  /// Build a single artwork image
  Widget _buildArtworkImage(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) => _buildFallbackArt(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildFallbackArt();
      },
    );
  }

  /// Fallback gradient with icon
  Widget _buildFallbackArt() {
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
          // Create new button with fixed square aspect ratio (same as albums)
          AspectRatio(
            aspectRatio: 1.0,
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
          const SizedBox(height: 4),
          // Label in expanded container (same as albums)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Playlist',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
