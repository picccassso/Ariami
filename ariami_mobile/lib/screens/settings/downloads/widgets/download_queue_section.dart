import 'package:flutter/material.dart';

import '../../../../models/download_task.dart';
import '../../../../services/download/download_manager.dart';
import 'download_item_card.dart';

/// Uppercase section title + list of [DownloadItemCard] (Active, Pending, Failed).
class DownloadQueueSection extends StatelessWidget {
  const DownloadQueueSection({
    super.key,
    required this.title,
    required this.tasks,
    required this.isDark,
    required this.progressByTaskId,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRetry,
  });

  final String title;
  final List<DownloadTask> tasks;
  final bool isDark;
  final Map<String, DownloadProgress> progressByTaskId;
  final void Function(String taskId) onPause;
  final Future<void> Function(String taskId) onResume;
  final void Function(String taskId) onCancel;
  final void Function(String taskId) onRetry;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...tasks.map((task) {
          return DownloadItemCard(
            task: task,
            isDark: isDark,
            progress: progressByTaskId[task.id],
            onPause: () => onPause(task.id),
            onResume: () => onResume(task.id),
            onCancel: () => onCancel(task.id),
            onRetry: () => onRetry(task.id),
          );
        }),
      ],
    );
  }
}
