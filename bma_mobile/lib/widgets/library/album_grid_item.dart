import 'package:flutter/material.dart';
import '../../models/api_models.dart';

/// Album grid item widget
/// Displays album artwork, title, and artist in a card format
class AlbumGridItem extends StatelessWidget {
  final AlbumModel album;
  final VoidCallback onTap;

  const AlbumGridItem({
    super.key,
    required this.album,
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
          // Album artwork with aspect ratio and shadow
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
                child: _buildAlbumArt(context),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Album title
          Text(
            album.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Artist name
          Text(
            album.artist,
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

  /// Build album artwork with loading and fallback
  Widget _buildAlbumArt(BuildContext context) {
    if (album.coverArt != null && album.coverArt!.isNotEmpty) {
      return Image.network(
        album.coverArt!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) {
            return child;
          }
          // Fade-in animation for artwork
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeIn,
            child: child,
          );
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
    // Generate a color based on album title for variety
    final colorIndex = album.title.hashCode % 5;
    final colors = [
      Colors.blue[300]!,
      Colors.purple[300]!,
      Colors.green[300]!,
      Colors.orange[300]!,
      Colors.pink[300]!,
    ];

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: colors[colorIndex],
      child: const Icon(
        Icons.album,
        size: 48,
        color: Colors.white,
      ),
    );
  }
}
