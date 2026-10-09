import 'package:flutter/material.dart';
import '../../../models/api_models.dart';
import '../../../services/api/connection_service.dart';
import '../../../widgets/common/cached_artwork.dart';

class AlbumArtWithBadge extends StatelessWidget {
  final SongModel song;

  final bool isDownloaded;

  final ConnectionService connectionService;

  const AlbumArtWithBadge({
    super.key,
    required this.song,
    required this.isDownloaded,
    required this.connectionService,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          _buildAlbumArt(),
          if (isDownloaded)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.green[600],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.download_done,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt() {
    String? artworkUrl;
    String cacheId;

    if (song.albumId != null) {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}'
          : null;
      cacheId = song.albumId!;
    } else {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${song.id}'
          : null;
      cacheId = 'song_${song.id}';
    }

    // Force square aspect ratio to ensure BoxFit.cover crops bars completely
    return AspectRatio(
      aspectRatio: 1.0,
      child: CachedArtwork(
        albumId: cacheId, // Used as cache key
        artworkUrl: artworkUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(4),
        fallback: _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.music_note, color: Colors.grey),
    );
  }
}
