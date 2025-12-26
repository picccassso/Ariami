import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../common/cached_artwork.dart';

/// Album grid item widget
/// Displays album artwork, title, and artist in a card format
class AlbumGridItem extends StatelessWidget {
  final AlbumModel album;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isAvailable;
  final bool hasDownloadedSongs;

  const AlbumGridItem({
    super.key,
    required this.album,
    this.onTap,
    this.onLongPress,
    this.isAvailable = true,
    this.hasDownloadedSongs = false,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = isAvailable ? 1.0 : 0.4;

    return Opacity(
      opacity: opacity,
      child: InkWell(
        onTap: isAvailable ? onTap : null,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Album artwork with fixed square aspect ratio
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
                child: _buildAlbumArt(context),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Album title and artist in expanded container to prevent overflow
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Album title
                Text(
                  album.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
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
          ),
        ],
      ),
      // Download indicator badge
      if (hasDownloadedSongs)
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.green[600],
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.download_done,
              size: 12,
              color: Colors.white,
            ),
          ),
        ),
          ],
        ),
      ),
    );
  }

  /// Build album artwork with loading and fallback (using CachedArtwork)
  Widget _buildAlbumArt(BuildContext context) {
    return CachedArtwork(
      albumId: album.id,
      artworkUrl: album.coverArt,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fallbackIconSize: 48,
    );
  }
}
