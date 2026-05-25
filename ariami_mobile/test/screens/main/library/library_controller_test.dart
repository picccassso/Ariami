import 'package:ariami_mobile/screens/main/library/library_controller.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_support/sqflite_mock.dart';

void main() {
  setUpAll(() async {
    installSqfliteTestMocks();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initializeSharedPrefs();
  });

  tearDownAll(uninstallSqfliteTestMocks);

  group('LibraryController load scheduling', () {
    late LibraryController controller;

    setUp(() {
      controller = LibraryController();
      controller.resetLoadSchedulingForTest();
    });

    test('queues deferred reload when library load is already in flight',
        () async {
      controller.markLibraryLoadInFlightForTest();

      await controller.loadLibraryForTest(background: true);

      expect(controller.isLibraryLoadInFlightForTest, isTrue);
      expect(controller.pendingBackgroundReloadForTest, isTrue);
    });

    test('chains a background reload after the in-flight load completes',
        () async {
      controller.markLibraryLoadInFlightForTest();
      await controller.loadLibraryForTest(background: true);

      await controller.completeLibraryLoadForTest();
      await Future<void>.delayed(Duration.zero);

      expect(controller.pendingBackgroundReloadForTest, isFalse);
      expect(controller.libraryLoadAttemptsForTest, equals(1));
    });

    test('defers sync-token refresh while load is in flight', () async {
      controller.markLibraryLoadInFlightForTest();

      final refreshed = await controller.refreshFromSyncTokenForTest(42);

      expect(refreshed, isFalse);
      expect(controller.pendingBackgroundReloadForTest, isTrue);
    });

    test('does not mark sync token handled when refresh is deferred', () async {
      controller.markLibraryLoadInFlightForTest();

      await controller.handleSyncTokenAdvancedForTest(42);

      expect(controller.lastHandledSyncTokenForTest, equals(0));
    });
  });
}
