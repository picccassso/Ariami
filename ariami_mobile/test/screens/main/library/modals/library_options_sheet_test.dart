import 'package:ariami_mobile/screens/main/library/library_controller.dart';
import 'package:ariami_mobile/screens/main/library/modals/library_options_sheet.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_support/sqflite_mock.dart';

void main() {
  setUpAll(() async {
    installSqfliteTestMocks();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initializeSharedPrefs();
  });

  tearDownAll(uninstallSqfliteTestMocks);

  group('LibraryOptionsSheet', () {
    late LibraryController controller;

    setUp(() {
      controller = LibraryController();
    });

    testWidgets('renders all controls and initial toggle states',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryOptionsSheet(
              controller: controller,
              isOffline: false,
              onRefresh: () {},
            ),
          ),
        ),
      );

      expect(find.text('Downloaded Only'), findsOneWidget);
      expect(find.text('Grid View'), findsOneWidget);
      expect(find.text('Mix Playlists & Albums'), findsOneWidget);
      expect(find.text('Select Multiple'), findsOneWidget);
      expect(find.text('Refresh Library'), findsOneWidget);

      final switches = tester
          .widgetList<SwitchListTile>(
            find.byType(SwitchListTile),
          )
          .toList();
      expect(switches.length, 3);
      expect(switches[0].value, controller.state.showDownloadedOnly);
      expect(switches[1].value, controller.state.isGridView);
      expect(switches[2].value, controller.state.isMixedMode);
    });

    testWidgets('toggles Downloaded Only live while sheet is rendered',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryOptionsSheet(
              controller: controller,
              isOffline: false,
              onRefresh: () {},
            ),
          ),
        ),
      );

      final initialDownloaded = controller.state.showDownloadedOnly;
      await tester.tap(find.text('Downloaded Only'));
      await tester.pump();

      expect(controller.state.showDownloadedOnly, !initialDownloaded);

      final switchTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Downloaded Only'),
      );
      expect(switchTile.value, !initialDownloaded);
    });

    testWidgets('toggles Grid View live while sheet is rendered',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryOptionsSheet(
              controller: controller,
              isOffline: false,
              onRefresh: () {},
            ),
          ),
        ),
      );

      final initialGridView = controller.state.isGridView;
      await tester.tap(find.text('Grid View'));
      await tester.pump();

      expect(controller.state.isGridView, !initialGridView);

      final switchTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Grid View'),
      );
      expect(switchTile.value, !initialGridView);
    });

    testWidgets('toggles Mix Playlists & Albums live while sheet is rendered',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryOptionsSheet(
              controller: controller,
              isOffline: false,
              onRefresh: () {},
            ),
          ),
        ),
      );

      final initialMixed = controller.state.isMixedMode;
      await tester.tap(find.text('Mix Playlists & Albums'));
      await tester.pump();

      expect(controller.state.isMixedMode, !initialMixed);

      final switchTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Mix Playlists & Albums'),
      );
      expect(switchTile.value, !initialMixed);
    });

    testWidgets('Select Multiple pops modal and enters selection mode',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showLibraryOptionsSheet(
                    context: context,
                    controller: controller,
                    isOffline: false,
                    onRefresh: () {},
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Library Options'), findsOneWidget);
      expect(controller.isSelectionModeActive, isFalse);

      await tester.tap(find.text('Select Multiple'));
      await tester.pumpAndSettle();

      expect(find.text('Library Options'), findsNothing);
      expect(controller.isSelectionModeActive, isTrue);
    });

    testWidgets('Refresh Library pops modal and invokes onRefresh when online',
        (tester) async {
      var refreshed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showLibraryOptionsSheet(
                    context: context,
                    controller: controller,
                    isOffline: false,
                    onRefresh: () => refreshed = true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Refresh Library'));
      await tester.pumpAndSettle();

      expect(find.text('Library Options'), findsNothing);
      expect(refreshed, isTrue);
    });

    testWidgets('Refresh Library is disabled when offline', (tester) async {
      var refreshed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryOptionsSheet(
              controller: controller,
              isOffline: true,
              onRefresh: () => refreshed = true,
            ),
          ),
        ),
      );

      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Refresh Library'),
      );
      expect(tile.enabled, isFalse);

      await tester.tap(find.text('Refresh Library'));
      await tester.pump();

      expect(refreshed, isFalse);
    });
  });
}
