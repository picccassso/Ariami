import 'package:flutter/material.dart';
import '../../../widgets/common/cached_artwork.dart';
import 'fallback_header.dart';

/// Artwork collage that displays 1, 2, or 4 artwork images in a grid layout
class ArtworkCollage extends StatelessWidget {
  /// List of artwork IDs to display (should be 1-4 items)
  final List<String> artworkIds;

  /// Base URL for artwork images (from connection service)
  final String? baseUrl;

  const ArtworkCollage({
    super.key,
    required this.artworkIds,
    this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (artworkIds.isEmpty) {
      return const FallbackHeader();
    }

    if (artworkIds.length == 1) {
      // Single artwork - fill entire header
      return _buildHeaderArtwork(artworkIds[0]);
    } else if (artworkIds.length == 2 || artworkIds.length == 3) {
      // Two artworks side by side
      return Row(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: _buildHeaderArtwork(artworkIds[0]),
            ),
          ),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: _buildHeaderArtwork(artworkIds[1]),
            ),
          ),
        ],
      );
    } else {
      // Four artworks in a 2x2 grid
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildHeaderArtwork(artworkIds[0]),
                ),
                Expanded(
                  child: _buildHeaderArtwork(artworkIds[1]),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildHeaderArtwork(artworkIds[2]),
                ),
                Expanded(
                  child: _buildHeaderArtwork(artworkIds[3]),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  /// Build a single artwork image for the header using CachedArtwork
  /// Handles both album IDs and standalone song IDs (prefixed with "song_")
  Widget _buildHeaderArtwork(String artworkId) {
    // Determine artwork URL based on ID type
    String? artworkUrl;
    if (baseUrl != null) {
      if (artworkId.startsWith('song_')) {
        // Standalone song - use song artwork endpoint
        final songId = artworkId.substring(5); // Remove "song_" prefix
        artworkUrl = '$baseUrl/song-artwork/$songId';
      } else {
        // Album - use album artwork endpoint
        artworkUrl = '$baseUrl/artwork/$artworkId';
      }
    }

    return CachedArtwork(
      albumId: artworkId, // Used as cache key
      artworkUrl: artworkUrl,
      fit: BoxFit.cover,
      fallback: const FallbackHeader(),
    );
  }
}
