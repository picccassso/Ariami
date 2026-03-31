import 'package:ariami_mobile/services/offline/offline_manual_reconnect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManualOfflineReconnectOutcome', () {
    test('matches Settings toggle-off branches', () {
      expect(
        ManualOfflineReconnectOutcome.values,
        containsAll(<ManualOfflineReconnectOutcome>[
          ManualOfflineReconnectOutcome.success,
          ManualOfflineReconnectOutcome.authFailure,
          ManualOfflineReconnectOutcome.networkFailure,
        ]),
      );
    });
  });

  group('LibraryRefreshOutcome', () {
    test('matches LibraryScreen refresh handling branches', () {
      expect(
        LibraryRefreshOutcome.values,
        containsAll(<LibraryRefreshOutcome>[
          LibraryRefreshOutcome.ok,
          LibraryRefreshOutcome.showSessionExpiredSnack,
          LibraryRefreshOutcome.showManualReconnectFailedSnack,
          LibraryRefreshOutcome.navigateToReconnectScreen,
        ]),
      );
    });
  });
}
