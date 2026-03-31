import 'package:flutter/material.dart';

import '../../../../models/download_task.dart';
import '../../../../services/api/connection_service.dart';
import '../../../../widgets/common/cached_artwork.dart';
import '../utils/download_helpers.dart';

class AlbumSongItem extends StatelessWidget {
  const AlbumSongItem({
    super.key,
    required this.task,
    required this.isDark,
    required this.isLast,
    required this.onRemove,
  });

  final DownloadTask task;
  final bool isDark;
  final bool isLast;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final connectionService = ConnectionService();

    String? artworkUrl;
    String cacheId;

    if (task.albumId != null) {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${task.albumId}'
          : null;
      cacheId = task.albumId!;
    } else {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${task.songId}'
          : null;
      cacheId = 'song_${task.songId}';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CachedArtwork(
                    albumId: cacheId,
                    artworkUrl: artworkUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    fallbackIcon: Icons.music_note_rounded,
                    fallbackIconSize: 20,
                    sizeHint: ArtworkSizeHint.thumbnail,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatBytes(task.bytesDownloaded),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: const Color(0xFFFF4B4B).withOpacity(0.8),
                    size: 16,
                  ),
                  onPressed: onRemove,
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFFF5F5F5),
                    shape: const CircleBorder(),
                  ),
                  tooltip: 'Remove song',
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 76.0, right: 16.0),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: isDark
                  ? const Color(0xFF1A1A1A).withOpacity(0.5)
                  : const Color(0xFFEEEEEE),
            ),
          ),
      ],
    );
  }
}
