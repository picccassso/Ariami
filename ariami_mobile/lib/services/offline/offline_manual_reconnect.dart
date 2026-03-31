import '../api/connection_service.dart';
import 'offline_playback_service.dart';

/// Result of exiting manual offline and calling [ConnectionService.tryRestoreConnection],
/// matching [SettingsScreen] toggle-off semantics.
enum ManualOfflineReconnectOutcome {
  success,
  authFailure,
  networkFailure,
}

/// Outcome of [LibraryController.refreshLibrary] so the UI can show snackbars or navigate.
enum LibraryRefreshOutcome {
  /// Library load finished; no extra UI action.
  ok,

  /// Same message as Settings when session/auth restore fails.
  showSessionExpiredSnack,

  /// Same message as Settings when server is unreachable after leaving manual offline.
  showManualReconnectFailedSnack,

  /// No saved server info — navigate to the full reconnect flow.
  navigateToReconnectScreen,
}

/// Disables manual offline optimistically, restores connection, and on hard failure
/// re-applies manual offline except for auth failures (same as Settings).
Future<ManualOfflineReconnectOutcome> reconnectFromManualOffline({
  required OfflinePlaybackService offline,
  required ConnectionService connection,
}) async {
  await offline.setManualOfflineMode(false);
  final restored = await connection.tryRestoreConnection();
  if (restored) {
    return ManualOfflineReconnectOutcome.success;
  }
  if (connection.didLastRestoreFailForAuth) {
    return ManualOfflineReconnectOutcome.authFailure;
  }
  await offline.setManualOfflineMode(true);
  return ManualOfflineReconnectOutcome.networkFailure;
}
