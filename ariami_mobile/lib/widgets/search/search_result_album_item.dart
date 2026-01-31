import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../common/cached_artwork.dart';

/// Search result item for albums
class SearchResultAlbumItem extends StatelessWidget {
  final AlbumModel album;
  final VoidCallback onTap;
  final String? searchQuery;

  const SearchResultAlbumItem({
    super.key,
    required this.album,
    required this.onTap,
    this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              // Large Album Art
              SizedBox(
                width: 60,
                height: 60,
                child: CachedArtwork(
                  albumId: album.id,
                  artworkUrl: album.coverArt,
                  width: 60,
                  height: 60,
                  borderRadius: BorderRadius.circular(12),
                  fallbackIconSize: 32,
                  sizeHint: ArtworkSizeHint.thumbnail,
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      album.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${album.artist} • ${album.songCount} song${album.songCount != 1 ? 's' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
