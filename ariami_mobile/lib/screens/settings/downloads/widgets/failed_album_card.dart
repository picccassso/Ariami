import 'package:flutter/material.dart';

import '../../../../models/download_task.dart';
import '../../../../widgets/common/cached_artwork.dart';
import '../downloads_state.dart';

/// Collapsible album row for the Failed section. Header shows the failure
/// count and a "Retry all" button; expanded body shows per-song error rows
/// each with their own retry / dismiss actions.
class FailedAlbumCard extends StatelessWidget {
  const FailedAlbumCard({
    super.key,
    required this.album,
    required this.isDark,
    required this.isLast,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onRetryAll,
    required this.onRetrySong,
    required this.onDismissSong,
  });

  final AlbumGroup album;
  final bool isDark;
  final bool isLast;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onRetryAll;
  final void Function(String taskId) onRetrySong;
  final void Function(String taskId) onDismissSong;

  @override
  Widget build(BuildContext context) {
    final retryableCount =
        album.songs.where((s) => s.canRetry()).length;

    return RepaintBoundary(
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
                        albumId: album.albumId ??
                            'song_${album.songs.first.songId}',
                        artworkUrl: album.albumArt.isNotEmpty
                            ? album.albumArt
                            : null,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        fallbackIcon: album.albumId == null
                            ? Icons.music_note_rounded
                            : Icons.album_rounded,
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
                          album.albumName,
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
                          album.albumArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color:
                                isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${album.failedCount} failed',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF4B4B),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (retryableCount > 0)
                    SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: onRetryAll,
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text('RETRY ALL'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFF1A1A1A)
                              : const Color(0xFFF5F5F5),
                          foregroundColor:
                              isDark ? Colors.white : Colors.black,
                          elevation: 0,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 32),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5),
                        ),
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
              color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.grey[50],
              child: Column(
                children: [
                  for (var i = 0; i < album.songs.length; i++)
                    _FailedSongRow(
                      key: ValueKey(album.songs[i].id),
                      task: album.songs[i],
                      isDark: isDark,
                      isLast: i == album.songs.length - 1,
                      onRetry: onRetrySong,
                      onDismiss: onDismissSong,
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
                color: isDark
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFEEEEEE),
              ),
            ),
        ],
      ),
    );
  }
}

class _FailedSongRow extends StatelessWidget {
  const _FailedSongRow({
    super.key,
    required this.task,
    required this.isDark,
    required this.isLast,
    required this.onRetry,
    required this.onDismiss,
  });

  final DownloadTask task;
  final bool isDark;
  final bool isLast;
  final void Function(String taskId) onRetry;
  final void Function(String taskId) onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: Icon(Icons.error_rounded,
                      size: 18, color: Color(0xFFFF4B4B)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.errorMessage ?? 'Download failed',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFF4B4B),
                      ),
                    ),
                  ],
                ),
              ),
              if (task.canRetry()) ...[
                const SizedBox(width: 8),
                _MiniIconButton(
                  icon: Icons.refresh_rounded,
                  isDark: isDark,
                  onPressed: () => onRetry(task.id),
                  tooltip: 'Retry',
                ),
              ],
              const SizedBox(width: 6),
              _MiniIconButton(
                icon: Icons.close_rounded,
                isDark: isDark,
                tint: const Color(0xFFFF4B4B),
                onPressed: () => onDismiss(task.id),
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 56, right: 16),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: isDark
                  ? const Color(0xFF1A1A1A).withValues(alpha: 0.5)
                  : const Color(0xFFEEEEEE),
            ),
          ),
      ],
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.isDark,
    required this.onPressed,
    required this.tooltip,
    this.tint,
  });

  final IconData icon;
  final bool isDark;
  final VoidCallback onPressed;
  final String tooltip;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(
          icon,
          size: 16,
          color:
              tint ?? (isDark ? Colors.white : Colors.black).withValues(alpha: 0.85),
        ),
        onPressed: onPressed,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor:
              isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}
