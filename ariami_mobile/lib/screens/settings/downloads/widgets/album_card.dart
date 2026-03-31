import 'package:flutter/material.dart';

import '../../../../models/download_task.dart';
import '../../../../widgets/common/cached_artwork.dart';
import '../utils/download_helpers.dart';
import 'album_song_item.dart';

class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.albumId,
    required this.songs,
    required this.isDark,
    required this.isLast,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onDeleteAlbum,
    required this.onRemoveSong,
  });

  final String albumId;
  final List<DownloadTask> songs;
  final bool isDark;
  final bool isLast;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onDeleteAlbum;
  final void Function(String taskId) onRemoveSong;

  @override
  Widget build(BuildContext context) {
    final firstSong = songs.first;
    final albumName = firstSong.albumName ?? 'Unknown Album';
    final albumArtist = firstSong.albumArtist ?? firstSong.artist;
    final totalBytes = calculateTotalBytes(songs);
    final artworkUrl = firstSong.albumArt;

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
                          child: CachedArtwork(
                            albumId: albumId,
                            artworkUrl:
                                artworkUrl.isNotEmpty ? artworkUrl : null,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            fallbackIcon: Icons.album_rounded,
                            fallbackIconSize: 24,
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
                              albumName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              albumArtist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                          onPressed: onDeleteAlbum,
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? const Color(0xFF1A1A1A)
                                : const Color(0xFFF5F5F5),
                            shape: const CircleBorder(),
                          ),
                          tooltip: 'Delete album',
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
