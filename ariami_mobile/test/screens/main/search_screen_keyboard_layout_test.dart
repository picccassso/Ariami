import 'package:ariami_mobile/screens/main/search_screen.dart';
import 'package:ariami_mobile/services/settings/search_settings_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  final searchSettings = SearchSettingsService();

  setUpAll(installSqfliteTestMocks);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeSharedPrefs();
    searchSettings.resetForTesting();
  });

  testWidgets('search scaffold does not resize above the keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.resizeToAvoidBottomInset, isFalse);
  });

  testWidgets('SearchScreen autofocuses by default in Spotify Mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(),
      ),
    );
    await tester.pump();

    TextField searchField() => tester.widget<TextField>(
          find.byType(TextField),
        );

    expect(searchField().focusNode?.hasFocus, isTrue);
  });

  testWidgets('SearchScreen does not autofocus on open in Standard Mode', (
    tester,
  ) async {
    await searchSettings.setMode(SearchMode.standard);

    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(),
      ),
    );
    await tester.pump();

    TextField searchField() => tester.widget<TextField>(
          find.byType(TextField),
        );

    expect(searchField().focusNode?.hasFocus, isFalse);
  });

  testWidgets(
    'search navigation focuses, submits, clears, then focuses again',
    (tester) async {
      final reselectionRequests = ValueNotifier<int>(0);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            focusOnOpen: true,
            reselectionRequests: reselectionRequests,
          ),
        ),
      );
      await tester.pump();

      TextField searchField() => tester.widget<TextField>(
            find.byType(TextField),
          );

      expect(searchField().focusNode?.hasFocus, isTrue);

      await tester.enterText(find.byType(TextField), 'Ariami');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(searchField().controller?.text, 'Ariami');
      expect(searchField().focusNode?.hasFocus, isFalse);

      reselectionRequests.value++;
      await tester.pump();

      expect(searchField().controller?.text, isEmpty);
      expect(searchField().focusNode?.hasFocus, isFalse);

      reselectionRequests.value++;
      await tester.pump();

      expect(searchField().focusNode?.hasFocus, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      reselectionRequests.dispose();
    },
  );

  testWidgets(
    'cancel button is visible when focused and tapping it clears and unfocuses',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SearchScreen(focusOnOpen: true),
        ),
      );
      await tester.pump();

      TextField searchField() => tester.widget<TextField>(
            find.byType(TextField),
          );

      expect(searchField().focusNode?.hasFocus, isTrue);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Test query');
      await tester.pump();
      expect(searchField().controller?.text, 'Test query');

      // Tap Cancel
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();

      expect(searchField().controller?.text, isEmpty);
      expect(searchField().focusNode?.hasFocus, isFalse);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
    },
  );

  testWidgets(
    'tapping blank space outside search field dismisses focus',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SearchScreen(focusOnOpen: true),
        ),
      );
      await tester.pump();

      TextField searchField() => tester.widget<TextField>(
            find.byType(TextField),
          );

      expect(searchField().focusNode?.hasFocus, isTrue);

      // Tap the empty space below search bar
      await tester.tapAt(const Offset(200, 400));
      await tester.pump();

      expect(searchField().focusNode?.hasFocus, isFalse);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
    },
  );
}
