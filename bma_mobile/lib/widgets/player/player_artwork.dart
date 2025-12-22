import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../services/api/connection_service.dart';
import '../common/cached_artwork.dart';

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

  /// Build artwork image or placeholder using CachedArtwork
  Widget _buildArtwork(BuildContext context) {
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
      fit: BoxFit.contain,
      width: 350,
      height: 350,
      fallback: _buildPlaceholder(context),
      fallbackIcon: Icons.music_note,
      fallbackIconSize: 120,
    );
  }

  /// Build placeholder artwork
  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: 350,
      height: 350,
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
