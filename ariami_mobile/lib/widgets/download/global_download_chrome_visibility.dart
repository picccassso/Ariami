import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/download_task.dart';
import '../../services/download/download_helpers.dart';
import '../../services/download/download_manager.dart';

/// Tracks whether the global download progress bar should occupy bottom chrome.
///
/// Visibility follows session-level queue state (pending/downloading/paused),
/// matching the Downloads screen "In Progress" section — not per-song completion.
/// [sessionProgress] exposes aggregate batch progress for a steady fill animation.
class GlobalDownloadChromeVisibility extends ChangeNotifier {
  GlobalDownloadChromeVisibility._internal();

  static final GlobalDownloadChromeVisibility instance =
      GlobalDownloadChromeVisibility._internal();

  static const Duration _flushInterval = Duration(milliseconds: 200);

  bool _isBarVisible = false;
  double? _sessionProgress;
  StreamSubscription<List<DownloadTask>>? _queueSubscription;
  StreamSubscription<DownloadProgress>? _progressSubscription;
  Timer? _flushTimer;
  bool _listening = false;

  final Map<String, double> _latestTaskProgress = {};

  bool get isBarVisible => _isBarVisible;

  /// Aggregate session progress in the range 0.0–1.0, or null when idle.
  double? get sessionProgress => _sessionProgress;

  void startListening() {
    if (_listening) {
      return;
    }
    _listening = true;

    final downloadManager = DownloadManager();
    final queue = downloadManager.queue;
    _seedSessionTasksIfNeeded(queue);
    _applyQueue(queue);
    _queueSubscription = downloadManager.queueStream.listen(_applyQueue);
    _progressSubscription =
        downloadManager.progressStream.listen(_onProgressEvent);
  }

  void _onProgressEvent(DownloadProgress event) {
    _latestTaskProgress[event.taskId] = event.progress;
    _scheduleProgressFlush();
  }

  void _scheduleProgressFlush() {
    if (_flushTimer?.isActive ?? false) {
      return;
    }
    _flushTimer = Timer(_flushInterval, () {
      _flushTimer = null;
      _recomputeSessionProgress(DownloadManager().queue);
    });
  }

  void _applyQueue(List<DownloadTask> queue) {
    final nextVisible = queueHasActiveDownloads(queue);

    if (!nextVisible && _isBarVisible) {
      DownloadManager().sessionTaskIds.clear();
      _latestTaskProgress.clear();
    }

    final visibilityChanged = nextVisible != _isBarVisible;
    _isBarVisible = nextVisible;

    final progressChanged = _updateSessionProgress(queue);

    if (visibilityChanged || progressChanged) {
      notifyListeners();
    }
  }

  void _seedSessionTasksIfNeeded(List<DownloadTask> queue) {
    if (!queueHasActiveDownloads(queue)) {
      return;
    }

    final sessionTaskIds = DownloadManager().sessionTaskIds;
    if (sessionTaskIds.isNotEmpty) {
      return;
    }

    for (final task in queue) {
      switch (task.status) {
        case DownloadStatus.pending:
        case DownloadStatus.downloading:
        case DownloadStatus.paused:
          sessionTaskIds.add(task.id);
        default:
          break;
      }
    }
  }

  bool _updateSessionProgress(List<DownloadTask> queue) {
    final nextProgress = computeSessionDownloadProgress(
      queue: queue,
      sessionTaskIds: DownloadManager().sessionTaskIds,
      latestTaskProgress: _latestTaskProgress,
    );

    if (nextProgress == _sessionProgress) {
      return false;
    }

    _sessionProgress = nextProgress;
    return true;
  }

  void _recomputeSessionProgress(List<DownloadTask> queue) {
    if (_updateSessionProgress(queue)) {
      notifyListeners();
    }
  }

  @visibleForTesting
  void debugApplyQueue(List<DownloadTask> queue) => _applyQueue(queue);

  @visibleForTesting
  void debugReset() {
    _queueSubscription?.cancel();
    _progressSubscription?.cancel();
    _flushTimer?.cancel();
    _queueSubscription = null;
    _progressSubscription = null;
    _flushTimer = null;
    _listening = false;
    _isBarVisible = false;
    _sessionProgress = null;
    _latestTaskProgress.clear();
  }
}
