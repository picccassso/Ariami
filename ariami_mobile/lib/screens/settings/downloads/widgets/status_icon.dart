import 'package:flutter/material.dart';

import '../../../../models/download_task.dart';

class StatusIcon extends StatelessWidget {
  const StatusIcon({
    super.key,
    required this.task,
    required this.isDark,
  });

  final DownloadTask task;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    switch (task.status) {
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle_filled_rounded,
            size: 22, color: Color(0xFFFFB300));
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle_rounded,
            size: 22, color: Color(0xFF00C853));
      case DownloadStatus.failed:
        return const Icon(Icons.error_rounded,
            size: 22, color: Color(0xFFFF4B4B));
      case DownloadStatus.pending:
      case DownloadStatus.cancelled:
        return Icon(Icons.schedule_rounded,
            size: 22,
            color: isDark ? Colors.grey[600] : Colors.grey[400]);
    }
  }
}
