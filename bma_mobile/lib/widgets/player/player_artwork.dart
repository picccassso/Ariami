import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../services/api/connection_service.dart';

/// Large album artwork with swipe gestures for track skipping
class PlayerArtwork extends StatelessWidget {
  final Song song;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  const PlayerArtwork({
    super.key,
    required this.song,
    required this.onSwipeLeft,
    required this.onSwipeRight,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe left (velocity > 0) = next track
        if (details.primaryVelocity! > 0) {
          onSwipeRight();
        }
        // Swipe right (velocity < 0) = previous track
        else if (details.primaryVelocity! < 0) {
          onSwipeLeft();
        }
      },
      child: Center(
        child: Hero(
          tag: 'album_art_${song.id}',
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 350,
              maxHeight: 350,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildArtwork(context),
            ),
          ),
        ),
      ),
    );
  }

  /// Build artwork image or placeholder
  Widget _buildArtwork(BuildContext context) {
    final connectionService = ConnectionService();

    // Try to load album artwork if song has albumId
    if (song.albumId != null && connectionService.apiClient != null) {
      final albumArtworkUrl = '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}';

      return Image.network(
        albumArtworkUrl,
        fit: BoxFit.cover,
        width: 350,
        height: 350,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(context);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildPlaceholder(context);
        },
      );
    }

    return _buildPlaceholder(context);
  }

  /// Build placeholder artwork
  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 120,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
        ),
      ),
    );
  }
}
