import 'dart:convert';

import 'package:ariami_mobile/models/quality_settings.dart';
import 'package:ariami_mobile/services/quality/quality_settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('QualitySettingsService download mode compatibility', () {
    test('setDownloadQuality to medium disables original downloads', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = QualitySettingsService();

      await service.initialize();
      await service.setDownloadOriginal(true);
      expect(service.getDownloadOriginal(), isTrue);

      await service.setDownloadQuality(StreamingQuality.medium);

      expect(service.getDownloadQuality(), StreamingQuality.medium);
      expect(service.getDownloadOriginal(), isFalse);
    });

    test(
      'setDownloadOriginal(true) is ignored when download quality is low',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final service = QualitySettingsService();

        await service.initialize();
        await service.setDownloadQuality(StreamingQuality.low);
        await service.setDownloadOriginal(true);

        expect(service.getDownloadQuality(), StreamingQuality.low);
        expect(service.getDownloadOriginal(), isFalse);
      },
    );

    test('initialize normalizes legacy incompatible saved settings', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'quality_settings': jsonEncode(<String, Object>{
          'wifiQuality': 'high',
          'mobileDataQuality': 'medium',
          'downloadQuality': 'medium',
          'preferLocalWhenOnline': false,
          'downloadOriginal': true,
        }),
      });
      final service = QualitySettingsService();

      await service.initialize();

      expect(service.getDownloadQuality(), StreamingQuality.medium);
      expect(service.getDownloadOriginal(), isFalse);

      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('quality_settings');
      expect(jsonString, isNotNull);
      final savedSettings = jsonDecode(jsonString!) as Map<String, dynamic>;
      expect(savedSettings['downloadOriginal'], isFalse);
    });
  });
}
