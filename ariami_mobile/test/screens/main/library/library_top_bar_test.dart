import 'package:ariami_mobile/screens/main/library_screen.dart';
import 'package:ariami_mobile/services/offline/offline_playback_service.dart';
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
      'LibraryScreen top bar shows single 3-dots options button and Downloaded chip on filter',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: LibraryScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Initially none of the old clutter icons should exist in the AppBar actions
    // (some may exist elsewhere in the body/tabs; only AppBar actions are checked)
    final optionsButton = find.byTooltip('Library Options');
    expect(optionsButton, findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);

    expect(find.byTooltip('Select Multiple'), findsNothing);
    expect(find.byTooltip('Show Downloaded Only'), findsNothing);
    expect(find.byTooltip('Show All Songs'), findsNothing);
    expect(find.byTooltip('Switch to List View'), findsNothing);
    expect(find.byTooltip('Switch to Grid View'), findsNothing);
    expect(find.byTooltip('Separate Playlists & Albums'), findsNothing);
    expect(find.byTooltip('Mix Playlists & Albums'), findsNothing);

    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.text('Downloaded')),
      findsNothing,
    );
    expect(
      find.descendant(of: appBar, matching: find.byType(Badge)),
      findsNothing,
    );

    await tester.tap(optionsButton);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Library Options'), findsOneWidget);
    expect(find.text('Downloaded Only'), findsOneWidget);

    await tester.tap(find.text('Downloaded Only'));
    await tester.pump(const Duration(milliseconds: 100));

    // Close the sheet by tapping the barrier
    await tester.tapAt(const Offset(20, 20));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.descendant(of: appBar, matching: find.text('Downloaded')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byType(Badge)),
      findsOneWidget,
    );

    await tester
        .tap(find.descendant(of: appBar, matching: find.text('Downloaded')));
    await tester.pump();

    expect(
      find.descendant(of: appBar, matching: find.text('Downloaded')),
      findsNothing,
    );
    expect(
      find.descendant(of: appBar, matching: find.byType(Badge)),
      findsNothing,
    );
  });

  testWidgets(
      'Tapping Select Multiple in options sheet transitions LibraryScreen to selection mode',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: LibraryScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final optionsButton = find.byTooltip('Library Options');
    await tester.tap(optionsButton);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Select Multiple'), findsOneWidget);
    await tester.tap(find.text('Select Multiple'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byTooltip('Cancel Selection'), findsOneWidget);
    expect(find.byTooltip('Select All'), findsOneWidget);
    expect(find.byTooltip('Deselect All'), findsOneWidget);
    expect(find.byTooltip('Library Options'), findsNothing);

    await tester.tap(find.byTooltip('Cancel Selection'));
    await tester.pump();

    expect(find.byTooltip('Library Options'), findsOneWidget);
    expect(find.byTooltip('Cancel Selection'), findsNothing);
  });

  testWidgets(
      'LibraryScreen top bar does not overflow on narrow screen with large text scale',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.8),
          ),
          child: child!,
        ),
        home: const LibraryScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final optionsButton = find.byTooltip('Library Options');
    await tester.tap(optionsButton);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Downloaded Only'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tapAt(const Offset(20, 20));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'LibraryScreen top bar does not overflow when both OFFLINE badge and Downloaded chip are active on narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await OfflinePlaybackService().setManualOfflineMode(true);
    addTearDown(() async {
      await OfflinePlaybackService().setManualOfflineMode(false);
      await OfflinePlaybackService().notifyConnectionRestored();
    });

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.8),
          ),
          child: child!,
        ),
        home: const LibraryScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('OFFLINE'), findsOneWidget);

    final optionsButton = find.byTooltip('Library Options');
    await tester.tap(optionsButton);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Since offline mode defaults showDownloadedOnly to true, toggle it if needed or check chip
    if (find
        .descendant(of: find.byType(AppBar), matching: find.text('Downloaded'))
        .evaluate()
        .isEmpty) {
      await tester.tap(find.text('Downloaded Only'));
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tapAt(const Offset(20, 20));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text('OFFLINE')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text('Downloaded')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
