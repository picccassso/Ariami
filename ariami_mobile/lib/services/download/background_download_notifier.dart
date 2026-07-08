import 'dart:async';
import 'dart:io';

import '../../models/download_task.dart';
import 'download_helpers.dart';
import 'download_manager.dart';
import 'native_download_service.dart';

/// Drives the persistent batch-download notification while the app is in the
/// background on Android.
///
/// The notification belongs to [AriamiDownloadNotificationService] (a
/// dedicated foreground service), not to individual download workers, so it
/// stays put across per-song completions. This class owns its content: it
/// watches the download queue and progress streams and pushes a throttled
/// "X of Y songs" summary, stopping the service (with a completion notice)
/// when the queue drains or the app returns to the foreground.
class BackgroundDownloadNotifier {
  BackgroundDownloadNotifier._();

  static final BackgroundDownloadNotifier instance =
      BackgroundDownloadNotifier._();

  static const Duration _updateInterval = Duration(seconds: 1);

  /// How long the notification survives a connection loss before giving up.
  /// While it lives, the foreground service keeps the process running, so
  /// the connection heartbeat can reconnect and auto-resume the batch.
  static const Duration _waitingForConnectionTimeout = Duration(minutes: 10);

  final DownloadManager _downloadManager = DownloadManager();
  final NativeDownloadService _nativeService = NativeDownloadService();

  StreamSubscription<List<DownloadTask>>? _queueSubscription;
  StreamSubscription<DownloadProgress>? _progressSubscription;
  Timer? _updateTimer;
  Timer? _waitingTimeoutTimer;
  bool _active = false;

  /// Raise the notification when the app leaves the foreground mid-batch.
  Future<void> onAppBackgrounded() async {
    if (!Platform.isAndroid || _active) return;
    if (!_downloadManager.hasActiveOrPendingDownloads) return;

    _active = true;
    final summary = _buildSummary();
    final started = await _nativeService.startBatchNotification(
      text: summary.text,
      progressPercent: summary.percent,
    );
    if (!started) {
      // Foreground start rejected/unavailable; workers fall back to their
      // own notification handling.
      _active = false;
      return;
    }

    _queueSubscription =
        _downloadManager.queueStream.listen((_) => _scheduleUpdate());
    _progressSubscription =
        _downloadManager.progressStream.listen((_) => _scheduleUpdate());
  }

  /// Drop the notification when the app is visible again — the in-app
  /// progress UI takes over.
  Future<void> onAppResumed() async {
    if (!_active) return;
    _teardown();
    await _nativeService.stopBatchNotification();
  }

  void _scheduleUpdate() {
    if (!_active) return;
    if (_updateTimer?.isActive ?? false) return;
    _updateTimer = Timer(_updateInterval, _pushUpdate);
  }

  Future<void> _pushUpdate() async {
    _updateTimer = null;
    if (!_active) return;

    if (!_downloadManager.hasActiveOrPendingDownloads) {
      // A connection loss auto-pauses the batch rather than ending it. Keep
      // the service (and with it the process and reconnect heartbeat) alive
      // so the batch can auto-resume, up to a timeout.
      if (_hasConnectionInterruptedDownloads()) {
        _startWaitingTimeout();
        final summary = _buildSummary();
        await _nativeService.updateBatchNotification(
          text: '${summary.text} — waiting for connection',
          progressPercent: summary.percent,
        );
        return;
      }

      final completedCount = _completedInSessionCount();
      _teardown();
      await _nativeService.stopBatchNotification(
        completionText: completedCount > 0
            ? 'Downloaded $completedCount '
                'song${completedCount == 1 ? '' : 's'}'
            : null,
      );
      return;
    }

    _waitingTimeoutTimer?.cancel();
    _waitingTimeoutTimer = null;
    final summary = _buildSummary();
    await _nativeService.updateBatchNotification(
      text: summary.text,
      progressPercent: summary.percent,
    );
  }

  bool _hasConnectionInterruptedDownloads() {
    return _downloadManager.queue.any((task) =>
        task.status == DownloadStatus.paused &&
        task.errorMessage == interruptedDownloadPauseMessage);
  }

  void _startWaitingTimeout() {
    if (_waitingTimeoutTimer?.isActive ?? false) return;
    _waitingTimeoutTimer = Timer(_waitingForConnectionTimeout, () async {
      if (!_active) return;
      if (_downloadManager.hasActiveOrPendingDownloads) return;
      _teardown();
      await _nativeService.stopBatchNotification();
    });
  }

  ({String text, int percent}) _buildSummary() {
    final queue = _downloadManager.queue;
    final sessionTaskIds = _downloadManager.sessionTaskIds;

    var inProgress = 0;
    var completedInSession = 0;
    for (final task in queue) {
      switch (task.status) {
        case DownloadStatus.downloading:
        case DownloadStatus.pending:
        case DownloadStatus.paused:
          inProgress++;
          break;
        case DownloadStatus.completed:
          if (sessionTaskIds.contains(task.id)) {
            completedInSession++;
          }
          break;
        case DownloadStatus.failed:
        case DownloadStatus.cancelled:
          break;
      }
    }

    final total = inProgress + completedInSession;
    final progress = computeSessionDownloadProgress(
      queue: queue,
      sessionTaskIds: sessionTaskIds,
    );
    return (
      text: '$completedInSession of $total song${total == 1 ? '' : 's'}',
      percent: progress == null ? -1 : (progress * 100).round(),
    );
  }

  int _completedInSessionCount() {
    final sessionTaskIds = _downloadManager.sessionTaskIds;
    if (sessionTaskIds.isEmpty) return 0;
    var count = 0;
    for (final task in _downloadManager.queue) {
      if (task.status == DownloadStatus.completed &&
          sessionTaskIds.contains(task.id)) {
        count++;
      }
    }
    return count;
  }

  void _teardown() {
    _active = false;
    _updateTimer?.cancel();
    _updateTimer = null;
    _waitingTimeoutTimer?.cancel();
    _waitingTimeoutTimer = null;
    _queueSubscription?.cancel();
    _queueSubscription = null;
    _progressSubscription?.cancel();
    _progressSubscription = null;
  }
}
