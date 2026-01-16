import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../services/api/connection_service.dart';
import '../common/cached_artwork.dart';

/// Playlist card widget
/// Displays playlist with dynamic mosaic artwork based on songs
class PlaylistCard extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// List of album IDs for the collage artwork (up to 4)
  /// CachedArtwork will handle fetching/caching and offline mode
  final List<String> albumIds;

  /// Whether this is the special "Liked Songs" playlist
  final bool isLikedSongs;

  /// Whether this playlist was imported from a server folder playlist
  final bool isImportedFromServer;

  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onLongPress,
    this.albumIds = const [],
    this.isLikedSongs = false,
    this.isImportedFromServer = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
                // Playlist name with optional imported indicator
                Row(
                  children: [
                    if (isImportedFromServer) ...[
                      Icon(
                        Icons.cloud_done,
                        size: 14,
                        color: Colors.blue[400],
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        playlist.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
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

  /// Build playlist artwork - custom image, collage, or fallback
  Widget _buildPlaylistArt() {
    // Priority 1: Custom user-selected image
    if (playlist.customImagePath != null) {
      final file = File(playlist.customImagePath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            // Fall back to collage/gradient if image fails to load
            return _buildArtworkCollage();
          },
        );
      }
    }

    // Priority 2: Album artwork collage or fallback
    return _buildArtworkCollage();
  }

  /// Build album artwork collage from songs
  Widget _buildArtworkCollage() {
    if (albumIds.isEmpty) {
      return _buildFallbackArt();
    }

    if (albumIds.length == 1) {
      // Single artwork
      return _buildArtworkImage(albumIds[0]);
    } else if (albumIds.length == 2 || albumIds.length == 3) {
      // Two artworks side by side - force square aspect ratio for each
      return Row(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: _buildArtworkImage(albumIds[0]),
            ),
          ),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: _buildArtworkImage(albumIds[1]),
            ),
          ),
        ],
      );
    } else {
      // Four artworks in a grid (2x2) - force square aspect ratio for each
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: _buildArtworkImage(albumIds[0]),
                  ),
                ),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: _buildArtworkImage(albumIds[1]),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: _buildArtworkImage(albumIds[2]),
                  ),
                ),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: _buildArtworkImage(albumIds[3]),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  /// Build a single artwork image using CachedArtwork
  /// Handles both album IDs and standalone song IDs (prefixed with "song_")
  Widget _buildArtworkImage(String artworkId) {
    final connectionService = ConnectionService();
    
    // Determine artwork URL based on ID type
    String? artworkUrl;
    if (artworkId.startsWith('song_')) {
      // Standalone song - use song artwork endpoint
      final songId = artworkId.substring(5); // Remove "song_" prefix
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/$songId'
          : null;
    } else {
      // Album - use album artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/$artworkId'
          : null;
    }

    return CachedArtwork(
      albumId: artworkId, // Used as cache key
      artworkUrl: artworkUrl,
      fit: BoxFit.cover,
      fallback: _buildFallbackArt(),
    );
  }

  /// Fallback gradient with icon
  Widget _buildFallbackArt() {
    // Special styling for Liked Songs
    if (isLikedSongs) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.pink[400]!, Colors.red[700]!],
          ),
        ),
        child: const Icon(
          Icons.favorite,
          size: 48,
          color: Colors.white,
        ),
      );
    }

    // Regular playlist fallback
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

/// Import from Server card widget
/// Shows when there are server folder playlists available to import
class ImportFromServerCard extends StatelessWidget {
  final int serverPlaylistCount;
  final VoidCallback onTap;

  const ImportFromServerCard({
    super.key,
    required this.serverPlaylistCount,
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
          // Import button with fixed square aspect ratio
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.blue[400]!, Colors.blue[700]!],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.cloud_download,
                    size: 40,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$serverPlaylistCount',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Label in expanded container
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import from Server',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.blue[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$serverPlaylistCount available',
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
}
