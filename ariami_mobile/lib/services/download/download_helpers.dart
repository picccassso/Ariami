import '../../models/download_task.dart';

/// Error marker used when downloads are auto-paused due to connectivity loss.
const String interruptedDownloadPauseMessage =
    'Paused because server connection was lost';

/// Error marker used when downloads are auto-paused when the app is closed.
const String appClosedDownloadPauseMessage = 'Paused because app was closed';

/// Returns true when a task was auto-paused due to interruption handling.
bool isInterruptedDownloadTask(DownloadTask task) {
  if (task.status != DownloadStatus.paused) {
    return false;
  }
  final reason = task.errorMessage;
  return reason == interruptedDownloadPauseMessage ||
      reason == appClosedDownloadPauseMessage;
}
