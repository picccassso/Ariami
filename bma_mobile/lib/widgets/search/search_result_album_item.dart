import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../services/api/connection_service.dart';

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
    final connectionService = ConnectionService();
    final artworkUrl = album.coverArt != null && connectionService.apiClient != null
        ? '${connectionService.apiClient!.baseUrl}/artwork/${album.coverArt}'
        : null;

    return ListTile(
      leading: SizedBox(
        width: 56,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: artworkUrl != null
              ? Image.network(
                  artworkUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildPlaceholder(context);
                  },
                )
              : _buildPlaceholder(context),
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

  /// Build placeholder for missing album art
  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: Icon(
        Icons.album,
        size: 32,
        color: Theme.of(context).primaryColor.withOpacity(0.3),
      ),
    );
  }
}
