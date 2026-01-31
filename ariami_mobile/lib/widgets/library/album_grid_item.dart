import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../common/cached_artwork.dart';

/// Album grid item widget
/// Displays album artwork, title, and artist in a premium layout
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
    // Dim unavailable items
    final opacity = isAvailable ? 1.0 : 0.4;

    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: isAvailable ? onTap : null,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Album Artwork Container
            AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                children: [
                   // Shadow & Container
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16), // Larger radius
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _buildAlbumArt(context),
                    ),
                  ),
                  
                  // Interactive Overlay (highlight on press - implicit via InkWell usually, but manual here for custom look if needed)
                  // For now, simple standard interaction is fine, effectively handled by GestureDetector
                  
                  // Download Indicator (Floating Badge)
                  if (hasDownloadedSongs)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.green, // Functional green for downloads
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                            )
                          ],
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
            
            const SizedBox(height: 12), // More breathing room
            
            // Text Details
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0), // Slight alignment correction
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      letterSpacing: -0.2, // Tighter tracking for modern look
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    album.artist,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
      sizeHint: ArtworkSizeHint.thumbnail,
    );
  }
}
