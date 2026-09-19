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

typedef SessionDownloadCounts = ({
  int completedSongs,
  int inProgressSongs,
  int totalSongs,
});

/// Counts only tasks belonging to the current user-visible batch and keeps the
/// server-resolved total fixed while paged job items enter the local queue.
SessionDownloadCounts computeSessionDownloadCounts({
  required Iterable<DownloadTask> queue,
  required Set<String> sessionTaskIds,
  int? expectedTaskCount,
}) {
  var completedSongs = 0;
  var inProgressSongs = 0;
  for (final task in queue) {
    if (!sessionTaskIds.contains(task.id)) continue;
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.pending:
      case DownloadStatus.paused:
        inProgressSongs++;
        break;
      case DownloadStatus.completed:
        completedSongs++;
        break;
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        break;
    }
  }

  final observedSongs = completedSongs + inProgressSongs;
  return (
    completedSongs: completedSongs,
    inProgressSongs: inProgressSongs,
    totalSongs: expectedTaskCount != null && expectedTaskCount > 0
        ? expectedTaskCount
        : observedSongs,
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
  int? expectedTaskCount,
  Map<String, double> latestTaskProgress = const {},
}) {
  final counts = computeSessionDownloadCounts(
    queue: queue,
    sessionTaskIds: sessionTaskIds,
    expectedTaskCount: expectedTaskCount,
  );
  var partialProgress = 0.0;

  for (final task in queue) {
    if (!sessionTaskIds.contains(task.id)) continue;
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.paused:
        partialProgress +=
            latestTaskProgress[task.id]?.clamp(0.0, 1.0) ?? task.progress;
        break;
      case DownloadStatus.pending:
        break;
      case DownloadStatus.completed:
        break;
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        break;
    }
  }

  if (counts.inProgressSongs == 0 || counts.totalSongs <= 0) {
    return null;
  }

  return ((counts.completedSongs + partialProgress) / counts.totalSongs)
      .clamp(0.0, 1.0);
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
