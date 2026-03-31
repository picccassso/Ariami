import 'package:flutter/material.dart';

import '../../../../models/download_task.dart';
import '../../../../services/download/download_manager.dart';
import '../utils/download_helpers.dart';
import 'action_buttons.dart';
import 'status_icon.dart';

class DownloadItemCard extends StatelessWidget {
  const DownloadItemCard({
    super.key,
    required this.task,
    required this.isDark,
    required this.progress,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRetry,
  });

  final DownloadTask task;
  final bool isDark;
  final DownloadProgress? progress;
  final VoidCallback onPause;
  final Future<void> Function() onResume;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: StatusIcon(task: task, isDark: isDark),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
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
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (task.status == DownloadStatus.downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress?.progress ?? task.progress,
                  minHeight: 6,
                  backgroundColor: isDark
                      ? const Color(0xFF1A1A1A)
                      : const Color(0xFFEEEEEE),
                  valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? Colors.white : Colors.black),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${progress?.percentage ?? task.getPercentage()}% • ${formatBytes(progress?.bytesDownloaded ?? task.bytesDownloaded)} / ${formatBytes(progress?.totalBytes ?? task.totalBytes)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  letterSpacing: 0.2,
                ),
              ),
            ] else if (task.status == DownloadStatus.completed) ...[
              const SizedBox(height: 12),
              Text(
                'Saved Locally • ${task.getFormattedTotalBytes()}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ] else if (task.status == DownloadStatus.failed) ...[
              const SizedBox(height: 12),
              Text(
                task.errorMessage ?? 'Download failed',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF4B4B),
                ),
              ),
            ],
            const SizedBox(height: 16),
            DownloadActionButtons(
              task: task,
              isDark: isDark,
              onPause: onPause,
              onResume: onResume,
              onCancel: onCancel,
              onRetry: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
