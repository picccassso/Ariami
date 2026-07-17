import 'package:ariami_mobile/screens/main/settings_screen.dart';
import 'package:ariami_mobile/services/audio/gapless_playback_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:ariami_mobile/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final gapless = GaplessPlaybackService();

  setUpAll(() {
    installSqfliteTestMocks();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async => '/tmp');
  });

  tearDownAll(() {
    uninstallSqfliteTestMocks();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeSharedPrefs();
    gapless.resetForTesting();
    PackageInfo.setMockInitialValues(
      appName: 'Ariami',
      packageName: 'com.example.ariamiMobile',
      version: '5.0.0',
      buildNumber: '8',
      buildSignature: '',
    );
  });

  testWidgets('shows the gapless switch above the equalizer and persists it',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );
    await tester.pumpAndSettle();

    final gaplessLabel = find.text('Gapless Playback');
    final equalizerLabel = find.text('Equalizer');
    expect(gaplessLabel, findsOneWidget);
    expect(equalizerLabel, findsOneWidget);
    expect(
      tester.getTopLeft(gaplessLabel).dy,
      lessThan(tester.getTopLeft(equalizerLabel).dy),
    );

    final gaplessTile = find.ancestor(
      of: gaplessLabel,
      matching: find.byType(SettingsTile),
    );
    final gaplessSwitch = find.descendant(
      of: gaplessTile,
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(gaplessSwitch).value, isTrue);

    await tester.tap(gaplessSwitch);
    await tester.pump();

    expect(tester.widget<Switch>(gaplessSwitch).value, isFalse);
    expect(
      sharedPrefs.getBool(GaplessPlaybackService.preferenceKey),
      isFalse,
    );
  });

  testWidgets('places Recently Played below Listening Statistics',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );
    await tester.pumpAndSettle();

    final stats = find.text('Listening Statistics');
    final recent = find.text('Recently Played');
    await tester.scrollUntilVisible(recent, 300);
    expect(stats, findsOneWidget);
    expect(recent, findsOneWidget);
    expect(find.text('Reset Statistics'), findsNothing);
    expect(
      tester.getTopLeft(stats).dy,
      lessThan(tester.getTopLeft(recent).dy),
    );
  });
}
