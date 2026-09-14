import 'package:ariami_mobile/screens/main/library/library_controller.dart';
import 'package:ariami_mobile/screens/main/library_screen.dart';
import 'package:ariami_mobile/screens/main/nested_tab_navigator.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter/material.dart';
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

  testWidgets(
      'Android back gesture in LibraryScreen cancels batch selection instead of exiting app',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    var exitedApp = false;

    final controller = LibraryController();

    await tester.pumpWidget(
      MaterialApp(
        home: NestedTabNavigator(
          navigatorKey: navKey,
          onBackAtRoot: () => exitedApp = true,
          onGenerateRoute: (settings) => MaterialPageRoute(
            settings: settings,
            builder: (_) => const LibraryScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Initially selection mode is inactive
    expect(controller.isSelectionModeActive, isFalse);

    // Enter selection mode and select items
    controller.enterSelectionMode();
    controller.toggleSongSelection('test-song-1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.isSelectionModeActive, isTrue);
    expect(controller.selectedSongIds, contains('test-song-1'));
    expect(find.text('1 selected'), findsOneWidget);

    // Simulate Android system back gesture (swipe back)
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    final handled = await widgetsAppState.didPopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Selection mode should be cancelled, songs cleared, and app should NOT have exited
    expect(handled, isTrue);
    expect(controller.isSelectionModeActive, isFalse);
    expect(controller.selectedSongIds, isEmpty);
    expect(exitedApp, isFalse);
    expect(find.text('1 selected'), findsNothing);

    // Second back gesture: with selection released, back gesture calls onBackAtRoot (exits app)
    final handledSecond = await widgetsAppState.didPopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(handledSecond, isTrue);
    expect(exitedApp, isTrue);
  });
}
