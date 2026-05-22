import 'dart:async';

import '../models/download_task.dart';
import '../services/download/download_manager.dart';

/// Listens to [DownloadManager.queueStream] and notifies when completed
/// downloads change, using the same debounce/signature pattern as [LibraryController].
class DownloadStateWatcher {
  DownloadStateWatcher({
    required void Function(Set<String> downloadedSongIds) onChanged,
    DownloadManager? downloadManager,
  })  : _onChanged = onChanged,
        _downloadManager = downloadManager ?? DownloadManager();

  final void Function(Set<String> downloadedSongIds) _onChanged;
  final DownloadManager _downloadManager;

  StreamSubscription<List<DownloadTask>>? _subscription;
  Timer? _refreshTimer;
  String _lastCompletedDownloadsSignature = '';

  /// Subscribe to queue updates and emit the current completed song IDs.
  void start() {
    _subscription?.cancel();
    _subscription = _downloadManager.queueStream.listen(_scheduleRefresh);
    _emitCurrent();
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _scheduleRefresh(List<DownloadTask> tasks) {
    final signature = buildCompletedDownloadsSignature(tasks);
    if (signature == _lastCompletedDownloadsSignature) return;

    _lastCompletedDownloadsSignature = signature;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 150), _emitCurrent);
  }

  void _emitCurrent() {
    final queue = _downloadManager.queue;
    _lastCompletedDownloadsSignature =
        buildCompletedDownloadsSignature(queue);
    _onChanged(completedSongIds(queue));
  }

  /// Returns song IDs for all completed download tasks in [queue].
  static Set<String> completedSongIds(List<DownloadTask> queue) {
    final downloadedIds = <String>{};
    for (final task in queue) {
      if (task.status == DownloadStatus.completed) {
        downloadedIds.add(task.songId);
      }
    }
    return downloadedIds;
  }

  /// Signature of completed downloads; only changes when a song completes.
  static String buildCompletedDownloadsSignature(List<DownloadTask> queue) {
    final buffer = StringBuffer();
    var completedCount = 0;

    for (final task in queue) {
      if (task.status != DownloadStatus.completed) continue;
      completedCount++;
      buffer
        ..write(task.id)
        ..write(':')
        ..write(task.albumId ?? '')
        ..write('|');
    }

    return '$completedCount#$buffer';
  }
}
