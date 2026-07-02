import 'dart:async';

import 'package:ariami_mobile/screens/settings/downloads/downloads_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('waits for the advertised sync token before refreshing counts',
      () async {
    final syncCompleted = Completer<void>();
    int? requestedToken;
    var refreshed = false;

    final coordinator = DownloadsLibraryRefreshCoordinator(
      canSync: () => true,
      syncNow: () async {},
      syncUntil: (targetToken) async {
        requestedToken = targetToken;
        await syncCompleted.future;
      },
    );

    final operation = coordinator.synchronizeAndRefresh(
      targetToken: 2072,
      refresh: () async {
        refreshed = true;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(requestedToken, 2072);
    expect(refreshed, isFalse);

    syncCompleted.complete();
    await operation;
    expect(refreshed, isTrue);
  });

  test('refreshes the local snapshot without syncing while disconnected',
      () async {
    var syncCalls = 0;
    var refreshCalls = 0;

    final coordinator = DownloadsLibraryRefreshCoordinator(
      canSync: () => false,
      syncNow: () async => syncCalls++,
      syncUntil: (_) async => syncCalls++,
    );

    await coordinator.synchronizeAndRefresh(
      targetToken: 99,
      refresh: () async => refreshCalls++,
    );

    expect(syncCalls, 0);
    expect(refreshCalls, 1);
  });
}
