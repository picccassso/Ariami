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
      // Single artwork — playlist detail uses a square expanded app bar (see playlist_detail_screen).
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
      // Four artworks: use a Stack so quadrants meet exactly (no flex seam / subpixel gap).
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final leftW = w * 0.5;
          final topH = h * 0.5;
          final rightW = w - leftW;
          final bottomH = h - topH;
          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: leftW,
                height: topH,
                child: _buildHeaderArtwork(artworkIds[0]),
              ),
              Positioned(
                left: leftW,
                top: 0,
                width: rightW,
                height: topH,
                child: _buildHeaderArtwork(artworkIds[1]),
              ),
              Positioned(
                left: 0,
                top: topH,
                width: leftW,
                height: bottomH,
                child: _buildHeaderArtwork(artworkIds[2]),
              ),
              Positioned(
                left: leftW,
                top: topH,
                width: rightW,
                height: bottomH,
                child: _buildHeaderArtwork(artworkIds[3]),
              ),
            ],
          );
        },
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
