import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../models/download_task.dart';
import '../../../../services/download/download_manager.dart';
import '../../../../widgets/common/cached_artwork.dart';
import '../downloads_state.dart';
import '../utils/download_helpers.dart';

/// Collapsible album row for the In Progress section. The header subscribes
/// to a per-album [AlbumProgressSnapshot] notifier so byte ticks update the
/// progress bar and percentage without rebuilding the rest of the screen.
/// Expanded body renders one [_InProgressSongRow] per song; each row
/// subscribes to its own per-task notifier (only the changing row repaints).
class InProgressAlbumCard extends StatelessWidget {
  const InProgressAlbumCard({
    super.key,
    required this.album,
    required this.isDark,
    required this.isLast,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.albumProgress,
    required this.taskProgressBuilder,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final AlbumGroup album;
  final bool isDark;
  final bool isLast;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final ValueListenable<AlbumProgressSnapshot> albumProgress;
  final ValueListenable<DownloadProgress> Function(DownloadTask task)
      taskProgressBuilder;
  final void Function(String taskId) onPause;
  final Future<void> Function(String taskId) onResume;
  final void Function(String taskId) onCancel;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        children: [
          InkWell(
            onTap: onToggleExpand,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _statsLine(album),
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
                      ValueListenableBuilder<AlbumProgressSnapshot>(
                        valueListenable: albumProgress,
                        builder: (context, snapshot, _) => Text(
                          '${snapshot.percentage}%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : Colors.black,
                            letterSpacing: 0.2,
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
                  const SizedBox(height: 10),
                  ValueListenableBuilder<AlbumProgressSnapshot>(
                    valueListenable: albumProgress,
                    builder: (context, snapshot, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: snapshot.bytesTotal > 0
                            ? snapshot.progress
                            : null,
                        minHeight: 4,
                        backgroundColor: isDark
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFFEEEEEE),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Container(
              color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey[50],
              child: Column(
                children: [
                  for (var i = 0; i < album.songs.length; i++)
                    _InProgressSongRow(
                      key: ValueKey(album.songs[i].id),
                      task: album.songs[i],
                      isDark: isDark,
                      isLast: i == album.songs.length - 1,
                      progress: taskProgressBuilder(album.songs[i]),
                      onPause: onPause,
                      onResume: onResume,
                      onCancel: onCancel,
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

  String _statsLine(AlbumGroup album) {
    final parts = <String>[];
    if (album.downloadingCount > 0) {
      parts.add('${album.downloadingCount} downloading');
    }
    if (album.queuedCount > 0) {
      parts.add('${album.queuedCount} queued');
    }
    if (album.pausedCount > 0) {
      parts.add('${album.pausedCount} paused');
    }
    if (parts.isEmpty) {
      parts.add('${album.totalCount} song${album.totalCount == 1 ? '' : 's'}');
    }
    return parts.join(' • ');
  }
}

class _InProgressSongRow extends StatelessWidget {
  const _InProgressSongRow({
    super.key,
    required this.task,
    required this.isDark,
    required this.isLast,
    required this.progress,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final DownloadTask task;
  final bool isDark;
  final bool isLast;
  final ValueListenable<DownloadProgress> progress;
  final void Function(String taskId) onPause;
  final Future<void> Function(String taskId) onResume;
  final void Function(String taskId) onCancel;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(child: _statusIndicator()),
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
                          if (task.trackNumber != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Track ${task.trackNumber}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (task.status == DownloadStatus.downloading ||
                        task.status == DownloadStatus.paused)
                      _SmallActionButton(
                        icon: task.status == DownloadStatus.downloading
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        isDark: isDark,
                        onPressed: () {
                          if (task.status == DownloadStatus.downloading) {
                            onPause(task.id);
                          } else {
                            onResume(task.id);
                          }
                        },
                      ),
                    if (task.status == DownloadStatus.downloading ||
                        task.status == DownloadStatus.paused ||
                        task.status == DownloadStatus.pending) ...[
                      const SizedBox(width: 6),
                      _SmallActionButton(
                        icon: Icons.close_rounded,
                        isDark: isDark,
                        tint: const Color(0xFFFF4B4B),
                        onPressed: () => onCancel(task.id),
                      ),
                    ],
                  ],
                ),
                if (task.status == DownloadStatus.downloading) ...[
                  const SizedBox(height: 8),
                  ValueListenableBuilder<DownloadProgress>(
                    valueListenable: progress,
                    builder: (context, value, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: value.totalBytes > 0
                                ? value.progress
                                : null,
                            minHeight: 3,
                            backgroundColor: isDark
                                ? const Color(0xFF1A1A1A)
                                : const Color(0xFFEEEEEE),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${value.percentage}% • ${formatBytes(value.bytesDownloaded)} / ${formatBytes(value.totalBytes)}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.grey[500]
                                : Colors.grey[600],
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (task.status == DownloadStatus.paused) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Paused',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFFB300),
                      letterSpacing: 0.3,
                    ),
                  ),
                ] else if (task.status == DownloadStatus.pending) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Queued',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
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
                    ? const Color(0xFF1A1A1A).withOpacity(0.5)
                    : const Color(0xFFEEEEEE),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusIndicator() {
    switch (task.status) {
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle_filled_rounded,
            size: 20, color: Color(0xFFFFB300));
      case DownloadStatus.pending:
        return Icon(Icons.schedule_rounded,
            size: 18,
            color: isDark ? Colors.grey[600] : Colors.grey[400]);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.icon,
    required this.isDark,
    required this.onPressed,
    this.tint,
  });

  final IconData icon;
  final bool isDark;
  final VoidCallback onPressed;
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
              tint ?? (isDark ? Colors.white : Colors.black).withOpacity(0.85),
        ),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor:
              isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}
