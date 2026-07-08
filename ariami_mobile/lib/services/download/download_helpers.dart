import '../../models/download_task.dart';

/// Error marker used when downloads are auto-paused due to connectivity loss.
const String interruptedDownloadPauseMessage =
    'Paused because server connection was lost';

/// Error marker used when downloads are auto-paused when the app is closed.
const String appClosedDownloadPauseMessage = 'Paused because app was closed';

/// Error marker used when downloads are auto-paused by app backgrounding.
const String lifecycleDownloadPauseMessage =
    'Paused because app was interrupted';

/// Transient marker used while an active Dart-side transfer is being handed
/// off to the native background backend. Tasks carry it only for the moment
/// between cancelling the in-app transfer and re-queueing it natively, so it
/// is deliberately not part of [isInterruptedDownloadTask].
const String backgroundHandoffPauseMessage =
    'Moving download to background service';

/// True while the queue has tasks that belong in the Downloads "In Progress"
/// section (pending, downloading, or paused).
bool queueHasActiveDownloads(Iterable<DownloadTask> queue) {
  return queue.any(
    (task) =>
        task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.pending ||
        task.status == DownloadStatus.paused,
  );
}

/// Aggregate batch progress for the global download bar and Downloads summary.
///
/// Matches the Downloads screen session model: [sessionTaskIds] anchors which
/// completed tasks count toward the current batch. In-progress tasks contribute
/// partial credit so the bar advances smoothly from start to finish.
double? computeSessionDownloadProgress({
  required List<DownloadTask> queue,
  required Set<String> sessionTaskIds,
  Map<String, double> latestTaskProgress = const {},
}) {
  if (!queueHasActiveDownloads(queue)) {
    return null;
  }

  var inProgressSongs = 0;
  var completedInSession = 0;
  var partialProgress = 0.0;

  for (final task in queue) {
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.paused:
        inProgressSongs++;
        partialProgress +=
            latestTaskProgress[task.id]?.clamp(0.0, 1.0) ?? task.progress;
        break;
      case DownloadStatus.pending:
        inProgressSongs++;
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

  final totalSongs = inProgressSongs + completedInSession;
  if (totalSongs <= 0) {
    return null;
  }

  return ((completedInSession + partialProgress) / totalSongs).clamp(0.0, 1.0);
}

/// Returns true when a task was auto-paused due to interruption handling.
bool isInterruptedDownloadTask(DownloadTask task) {
  if (task.status != DownloadStatus.paused) {
    return false;
  }
  final reason = task.errorMessage;
  return reason == interruptedDownloadPauseMessage ||
      reason == appClosedDownloadPauseMessage ||
      reason == lifecycleDownloadPauseMessage;
}
