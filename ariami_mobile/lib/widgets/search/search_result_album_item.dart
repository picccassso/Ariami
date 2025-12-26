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
    return ListTile(
      leading: SizedBox(
        width: 56,
        height: 56,
        child: CachedArtwork(
          albumId: album.id,
          artworkUrl: album.coverArt,
          width: 56,
          height: 56,
          borderRadius: BorderRadius.circular(4),
          fallbackIconSize: 32,
        ),
      ),
      title: Text(
        album.title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${album.artist} • ${album.songCount} song${album.songCount != 1 ? 's' : ''}',
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[600],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
