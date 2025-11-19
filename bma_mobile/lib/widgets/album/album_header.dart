import 'package:flutter/material.dart';

/// Album artwork header with parallax effect
/// Used in album detail screen's SliverAppBar
class AlbumArtworkHeader extends StatelessWidget {
  final String? coverArt;
  final String albumTitle;

  const AlbumArtworkHeader({
    super.key,
    this.coverArt,
    required this.albumTitle,
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
    print('[AlbumArtworkHeader] coverArt URL: $coverArt');
    print('[AlbumArtworkHeader] coverArt is null: ${coverArt == null}');
    print('[AlbumArtworkHeader] coverArt is empty: ${coverArt?.isEmpty}');

    if (coverArt != null && coverArt!.isNotEmpty) {
      print('[AlbumArtworkHeader] Loading image from: $coverArt');
      return Image.network(
        coverArt!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            print('[AlbumArtworkHeader] Image loaded successfully!');
            return child;
          }
          print('[AlbumArtworkHeader] Loading... ${loadingProgress.cumulativeBytesLoaded}/${loadingProgress.expectedTotalBytes}');
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) {
          print('[AlbumArtworkHeader] ERROR loading image: $error');
          print('[AlbumArtworkHeader] Stack trace: $stackTrace');
          return _buildFallbackArt();
        },
      );
    } else {
      print('[AlbumArtworkHeader] Using fallback art (no URL provided)');
      return _buildFallbackArt();
    }
  }

  /// Fallback artwork when no cover art is available
  Widget _buildFallbackArt() {
    // Generate a color based on album title
    final colorIndex = albumTitle.hashCode % 5;
    final colors = [
      Colors.blue[700]!,
      Colors.purple[700]!,
      Colors.green[700]!,
      Colors.orange[700]!,
      Colors.pink[700]!,
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
