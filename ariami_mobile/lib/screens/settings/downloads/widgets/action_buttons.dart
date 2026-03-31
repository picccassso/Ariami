import 'package:flutter/material.dart';

import '../../../../models/download_task.dart';

class DownloadActionButtons extends StatelessWidget {
  const DownloadActionButtons({
    super.key,
    required this.task,
    required this.isDark,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRetry,
  });

  final DownloadTask task;
  final bool isDark;
  final VoidCallback onPause;
  final Future<void> Function() onResume;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor:
          isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
      foregroundColor: isDark ? Colors.white : Colors.black,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      minimumSize: const Size(0, 36),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
    );

    if (task.status == DownloadStatus.downloading) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: onPause,
          icon: const Icon(Icons.pause_rounded, size: 14),
          label: const Text('PAUSE'),
          style: buttonStyle,
        ),
      );
      buttons.add(const SizedBox(width: 8));
      buttons.add(
        ElevatedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close_rounded, size: 14),
          label: const Text('CANCEL'),
          style: buttonStyle.copyWith(
            foregroundColor: WidgetStateProperty.all(const Color(0xFFFF4B4B)),
          ),
        ),
      );
    } else if (task.status == DownloadStatus.paused) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => onResume(),
          icon: const Icon(Icons.play_arrow_rounded, size: 14),
          label: const Text('RESUME'),
          style: buttonStyle,
        ),
      );
      buttons.add(const SizedBox(width: 8));
      buttons.add(
        ElevatedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close_rounded, size: 14),
          label: const Text('CANCEL'),
          style: buttonStyle.copyWith(
            foregroundColor: WidgetStateProperty.all(const Color(0xFFFF4B4B)),
          ),
        ),
      );
    } else if (task.status == DownloadStatus.failed && task.canRetry()) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 14),
          label: const Text('RETRY'),
          style: buttonStyle,
        ),
      );
    } else if (task.status == DownloadStatus.completed) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.delete_outline_rounded, size: 14),
          label: const Text('REMOVE'),
          style: buttonStyle.copyWith(
            foregroundColor: WidgetStateProperty.all(const Color(0xFFFF4B4B)),
          ),
        ),
      );
    } else if (task.status == DownloadStatus.pending) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close_rounded, size: 14),
          label: const Text('REMOVE'),
          style: buttonStyle.copyWith(
            foregroundColor: WidgetStateProperty.all(const Color(0xFFFF4B4B)),
          ),
        ),
      );
    }

    return Row(children: buttons);
  }
}
