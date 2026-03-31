import 'package:flutter/material.dart';

import '../../../../models/download_task.dart';
import '../../../../services/api/connection_service.dart';
import '../../../../widgets/common/cached_artwork.dart';
import '../utils/download_helpers.dart';
import 'album_song_item.dart';

class SinglesCard extends StatelessWidget {
  const SinglesCard({
    super.key,
    required this.songs,
    required this.isDark,
    required this.isLast,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onDeleteSingles,
    required this.onRemoveSong,
  });

  final List<DownloadTask> songs;
  final bool isDark;
  final bool isLast;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onDeleteSingles;
  final void Function(String taskId) onRemoveSong;

  static const singlesKey = 'singles';

  @override
  Widget build(BuildContext context) {
    final totalBytes = calculateTotalBytes(songs);
    final connectionService = ConnectionService();

    final firstSong = songs.isNotEmpty ? songs.first : null;
    final artworkUrl = firstSong != null && connectionService.apiClient != null
        ? '${connectionService.apiClient!.baseUrl}/song-artwork/${firstSong.songId}'
        : null;
    final cacheId = firstSong != null ? 'song_${firstSong.songId}' : '';

    return Column(
      children: [
        Container(
          color: Colors.transparent,
          child: Column(
            children: [
              InkWell(
                onTap: onToggleExpand,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child: firstSong != null
                              ? CachedArtwork(
                                  albumId: cacheId,
                                  artworkUrl: artworkUrl,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  fallbackIcon: Icons.music_note_rounded,
                                  fallbackIconSize: 24,
                                  sizeHint: ArtworkSizeHint.thumbnail,
                                )
                              : Container(
                                  color: isDark
                                      ? const Color(0xFF1A1A1A)
                                      : const Color(0xFFF5F5F5),
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    color: isDark
                                        ? Colors.grey[700]
                                        : Colors.grey[400],
                                    size: 24,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Singles',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Songs without album',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${songs.length} songs • ${formatBytes(totalBytes)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[500],
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: const Color(0xFFFF4B4B).withOpacity(0.8),
                            size: 20,
                          ),
                          onPressed: onDeleteSingles,
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? const Color(0xFF1A1A1A)
                                : const Color(0xFFF5F5F5),
                            shape: const CircleBorder(),
                          ),
                          tooltip: 'Delete all singles',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                Container(
                  color:
                      isDark ? Colors.black.withOpacity(0.3) : Colors.grey[50],
                  child: Column(
                    children: songs.asMap().entries.map((entry) {
                      final index = entry.key;
                      final song = entry.value;
                      final isLastSong = index == songs.length - 1;
                      return AlbumSongItem(
                        task: song,
                        isDark: isDark,
                        isLast: isLastSong,
                        onRemove: () => onRemoveSong(song.id),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE),
            ),
          ),
      ],
    );
  }
}
