import 'dart:convert';

import 'package:ariami_mobile/models/quality_settings.dart';
import 'package:ariami_mobile/screens/settings/quality_settings_screen.dart';
import 'package:ariami_mobile/services/quality/network_monitor_service.dart';
import 'package:ariami_mobile/services/quality/quality_settings_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installSqfliteTestMocks();

  const connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity');
  const connectivityStatusChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity_status');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
      if (call.method == 'check') {
        return <String>['wifi'];
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityStatusChannel, (call) async {
      if (call.method == 'listen' || call.method == 'cancel') {
        return null;
      }
      return null;
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityStatusChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeSharedPrefs();
    NetworkMonitorService().resetForTesting();
    QualitySettingsService().resetToDefaults();
  });

  testWidgets('renders download quality section and opens 4-option picker',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QualitySettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DOWNLOAD QUALITY'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('High (192 kbps)'), findsOneWidget);

    // Tap Downloads tile to open bottom sheet
    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();

    // Verify all 4 options are present in the sheet
    expect(find.widgetWithText(ListTile, 'Original'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'High (192 kbps)'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Medium (128 kbps)'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Low (64 kbps)'), findsOneWidget);

    // Select Original
    await tester.tap(find.widgetWithText(ListTile, 'Original'));
    await tester.pumpAndSettle();

    // Sheet should be dismissed and Downloads tile now shows Original
    expect(find.text('Original'), findsOneWidget);
    final service = QualitySettingsService();
    expect(service.getEffectiveDownloadQuality(), DownloadQuality.original);
    expect(service.getDownloadOriginal(), isTrue);
  });

  testWidgets('allows selecting Medium download quality', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QualitySettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Medium (128 kbps)'));
    await tester.pumpAndSettle();

    final service = QualitySettingsService();
    expect(service.getEffectiveDownloadQuality(), DownloadQuality.medium);
    expect(service.getDownloadOriginal(), isFalse);
    expect(service.getDownloadQuality(), StreamingQuality.medium);
  });

  testWidgets(
      'displays Original when downloadOriginal is true in saved settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'quality_settings': jsonEncode({
        'wifiQuality': 'high',
        'mobileDataQuality': 'medium',
        'downloadQuality': 'high',
        'preferLocalWhenOnline': false,
        'downloadOriginal': true,
      }),
    });
    await initializeSharedPrefs();

    await tester.pumpWidget(
      const MaterialApp(
        home: QualitySettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DOWNLOAD QUALITY'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
  });

  testWidgets('updates dynamically when quality settings change externally',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QualitySettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('High (192 kbps)'), findsOneWidget);

    // Update settings externally via QualitySettingsService
    await QualitySettingsService()
        .setDownloadQualityOption(DownloadQuality.low);
    await tester.pumpAndSettle();

    expect(find.text('Low (64 kbps)'), findsOneWidget);
  });
}
