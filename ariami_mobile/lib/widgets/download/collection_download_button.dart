import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/download_task.dart';
import '../../services/download/download_manager.dart';

/// Live download state for an album or playlist.
class CollectionDownloadState {
  const CollectionDownloadState({
    required this.completed,
    required this.inProgress,
    required this.progress,
  });

  final int completed;
  final bool inProgress;
  final double progress;
}

/// Calculates collection-wide progress, counting completed songs as 100% and
/// active songs by their latest fractional progress.
CollectionDownloadState calculateCollectionDownloadState({
  required Iterable<String> songIds,
  required Iterable<DownloadTask> tasks,
  Map<String, double> latestTaskProgress = const {},
}) {
  final progressBySong = <String, double>{};
  final activeSongIds = <String>{};

  for (final task in tasks) {
    if (task.status == DownloadStatus.completed) {
      progressBySong[task.songId] = 1;
      continue;
    }

    final isActive = task.status == DownloadStatus.pending ||
        task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.paused;
    if (!isActive) continue;

    activeSongIds.add(task.songId);
    final progress = latestTaskProgress[task.id] ?? task.progress;
    final current = progressBySong[task.songId] ?? 0;
    if (progress > current) {
      progressBySong[task.songId] = progress.clamp(0.0, 1.0);
    }
  }

  var completed = 0;
  var inProgress = false;
  var totalProgress = 0.0;
  var total = 0;

  for (final songId in songIds) {
    total++;
    final progress = progressBySong[songId] ?? 0;
    if (progress >= 1) completed++;
    if (activeSongIds.contains(songId)) inProgress = true;
    totalProgress += progress;
  }

  return CollectionDownloadState(
    completed: completed,
    inProgress: inProgress,
    progress: total == 0 ? 0 : (totalProgress / total).clamp(0.0, 1.0),
  );
}

/// Album/playlist download button with live collection-wide progress.
class CollectionDownloadButton extends StatefulWidget {
  const CollectionDownloadButton({
    super.key,
    required this.songIds,
    required this.isFullyDownloaded,
    required this.onPressed,
    this.onCancel,
    this.collectionLabel = 'collection',
    this.iconSize = 28,
  });

  final List<String> songIds;
  final bool isFullyDownloaded;
  final VoidCallback? onPressed;
  final VoidCallback? onCancel;
  final String collectionLabel;
  final double iconSize;

  @override
  State<CollectionDownloadButton> createState() =>
      _CollectionDownloadButtonState();
}

class _CollectionDownloadButtonState extends State<CollectionDownloadButton> {
  static const _progressRefreshInterval = Duration(milliseconds: 120);

  final DownloadManager _downloadManager = DownloadManager();
  final Map<String, double> _latestTaskProgress = {};

  StreamSubscription<List<DownloadTask>>? _queueSubscription;
  StreamSubscription<DownloadProgress>? _progressSubscription;
  Timer? _progressRefreshTimer;

  @override
  void initState() {
    super.initState();
    _queueSubscription = _downloadManager.queueStream.listen((tasks) {
      final taskIds = tasks.map((task) => task.id).toSet();
      _latestTaskProgress.removeWhere((taskId, _) => !taskIds.contains(taskId));
      if (mounted) setState(() {});
    });
    _progressSubscription = _downloadManager.progressStream.listen((event) {
      _latestTaskProgress[event.taskId] = event.progress;
      if (_progressRefreshTimer?.isActive ?? false) return;
      _progressRefreshTimer = Timer(_progressRefreshInterval, () {
        _progressRefreshTimer = null;
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    _progressSubscription?.cancel();
    _progressRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.songIds.isEmpty
        ? const CollectionDownloadState(
            completed: 0,
            inProgress: false,
            progress: 0,
          )
        : calculateCollectionDownloadState(
            songIds: widget.songIds,
            tasks: _downloadManager.queue,
            latestTaskProgress: _latestTaskProgress,
          );
    final isFullyDownloaded = widget.isFullyDownloaded ||
        (widget.songIds.isNotEmpty &&
            state.completed >= widget.songIds.length);

    if (state.inProgress) {
      return IconButton(
        tooltip: 'Cancel download — ${state.completed} of '
            '${widget.songIds.length} done',
        onPressed: widget.onCancel,
        iconSize: widget.iconSize,
        icon: SizedBox(
          width: widget.iconSize,
          height: widget.iconSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: state.progress),
                duration: const Duration(milliseconds: 180),
                builder: (context, progress, _) => CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.5,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.2),
                ),
              ),
              Icon(Icons.stop_rounded, size: widget.iconSize * 0.52),
            ],
          ),
        ),
      );
    }

    return IconButton(
      tooltip: isFullyDownloaded
          ? 'Downloaded — tap to remove'
          : 'Download ${widget.collectionLabel}',
      onPressed: widget.onPressed,
      iconSize: widget.iconSize,
      icon: Icon(
        isFullyDownloaded
            ? Icons.download_done_rounded
            : Icons.download_for_offline_outlined,
        color: isFullyDownloaded ? Colors.green : null,
      ),
    );
  }
}
