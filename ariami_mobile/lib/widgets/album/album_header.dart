import 'package:flutter/material.dart';
import '../common/cached_artwork.dart';

/// Album artwork header with parallax effect
/// Used in album detail screen's SliverAppBar
class AlbumArtworkHeader extends StatelessWidget {
  final String? coverArt;
  final String albumTitle;
  final String? albumId;

  const AlbumArtworkHeader({
    super.key,
    this.coverArt,
    required this.albumTitle,
    this.albumId,
  });

  @override
  Widget build(BuildContext context) {
    return FlexibleSpaceBar(
      background: Stack(
        fit: StackFit.expand,
        children: [
          // Album artwork (parallax effect handled by SliverAppBar)
          _buildArtwork(),

          // Gradient overlay for text readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build album artwork with fallback
  Widget _buildArtwork() {
    // If we have an albumId, use CachedArtwork for automatic caching
    // CachedArtwork checks cache first, so it works even without a URL (offline mode)
    if (albumId != null) {
      return SizedBox.expand(
        child: CachedArtwork(
          albumId: albumId!,
          artworkUrl: coverArt,
          fit: BoxFit.cover,
          fallback: _buildFallbackArt(),
        ),
      );
    }

    // Fallback for when no albumId is available
    if (coverArt != null && coverArt!.isNotEmpty) {
      return Image.network(
        coverArt!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackArt();
        },
      );
    } else {
      return _buildFallbackArt();
    }
  }

  /// Fallback artwork when no cover art is available
  Widget _buildFallbackArt() {
    // Generate a color based on album title
    final colorIndex = albumTitle.hashCode % 5;
    final colors = [
      Colors.grey[900]!,
      Colors.grey[800]!,
      Colors.grey[700]!,
      Colors.grey[600]!,
      Colors.grey[850]!,
    ];

    return Container(
      color: colors[colorIndex],
      child: const Center(
        child: Icon(
          Icons.album,
          size: 120,
          color: Colors.white,
        ),
      ),
    );
  }
}
