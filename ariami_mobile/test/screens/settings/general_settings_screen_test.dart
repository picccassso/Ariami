import 'package:ariami_mobile/screens/settings/general_settings_screen.dart';
import 'package:ariami_mobile/services/settings/search_settings_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installSqfliteTestMocks();

  final searchSettings = SearchSettingsService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeSharedPrefs();
    searchSettings.resetForTesting();
  });

  testWidgets('displays Search Mode setting and allows changing mode',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GeneralSettingsScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('GENERAL'), findsOneWidget);
    expect(find.text('Search Mode'), findsOneWidget);
    expect(find.text('Spotify Mode'), findsOneWidget);

    // Tap Search Mode tile to open dialog
    await tester.tap(find.text('Search Mode'));
    await tester.pumpAndSettle();

    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Spotify Mode'), findsWidgets);

    // Select Standard mode
    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed and subtitle updated to Standard
    expect(find.text('Standard'), findsOneWidget);
    expect(searchSettings.mode, SearchMode.standard);
  });

  testWidgets('displays Recent Searches Limit tile with initial Standard (30)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GeneralSettingsScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent Searches Limit'), findsOneWidget);
    expect(find.text('Standard (30)'), findsOneWidget);
  });

  testWidgets('allows changing Recent Searches Limit to Custom and validates range',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GeneralSettingsScreen()),
    );
    await tester.pumpAndSettle();

    // Tap Recent Searches Limit tile to open dialog
    await tester.tap(find.text('Recent Searches Limit'));
    await tester.pumpAndSettle();

    expect(find.text('Recent Searches Limit'), findsWidgets);
    expect(find.text('Standard (30)'), findsWidgets);
    expect(find.text('Custom'), findsOneWidget);

    // Tap Custom option
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    // Custom limit text field is displayed
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);

    // Test validation: enter invalid value < 5
    await tester.enterText(textField, '3');
    await tester.pumpAndSettle();
    expect(find.text('Enter a number between 5 and 500'), findsOneWidget);

    // Tapping Save with invalid input should not dismiss dialog
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a number between 5 and 500'), findsOneWidget);

    // Enter valid value in range (e.g. 50)
    await tester.enterText(textField, '50');
    await tester.pumpAndSettle();
    expect(find.text('Enter a number between 5 and 500'), findsNothing);

    // Tap Save
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Dialog is dismissed and tile subtitle updated to Custom (50)
    expect(find.text('Custom (50)'), findsOneWidget);
    expect(searchSettings.isCustomRecentLimit, isTrue);
    expect(searchSettings.recentSearchesLimit, 50);

    // Reopen dialog and switch back to Standard (30)
    await tester.tap(find.text('Recent Searches Limit'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standard (30)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Standard (30)'), findsOneWidget);
    expect(searchSettings.isCustomRecentLimit, isFalse);
    expect(searchSettings.recentSearchesLimit, 30);
  });

  testWidgets('cancelling Recent Searches Limit dialog discards changes',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GeneralSettingsScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recent Searches Limit'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '75');
    await tester.pumpAndSettle();

    // Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Still Standard (30)
    expect(find.text('Standard (30)'), findsOneWidget);
    expect(searchSettings.isCustomRecentLimit, isFalse);
    expect(searchSettings.recentSearchesLimit, 30);
  });

  testWidgets('rapidly toggling between Standard and Custom preserves correct state',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GeneralSettingsScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recent Searches Limit'));
    await tester.pumpAndSettle();

    final standardOption = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Standard (30)'),
    );
    final customOption = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Custom'),
    );

    // Rapid taps
    await tester.tap(customOption);
    await tester.pump();
    await tester.tap(standardOption);
    await tester.pump();
    await tester.tap(customOption);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '25');
    await tester.pumpAndSettle();

    // Toggle back to Standard
    await tester.tap(standardOption);
    await tester.pumpAndSettle();

    // Save while Standard is selected
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Standard (30)'), findsOneWidget);
    expect(searchSettings.isCustomRecentLimit, isFalse);
    expect(searchSettings.recentSearchesLimit, 30);
  });
}
