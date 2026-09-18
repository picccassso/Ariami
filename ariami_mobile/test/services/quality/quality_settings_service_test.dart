import 'dart:convert';

import 'package:ariami_mobile/models/quality_settings.dart';
import 'package:ariami_mobile/services/quality/quality_settings_service.dart';
import 'package:ariami_mobile/services/quality/network_monitor_service.dart';
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
      'setDownloadOriginal(true) selects the separate original mode',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final service = QualitySettingsService();

        await service.initialize();
        await service.setDownloadQuality(StreamingQuality.low);
        await service.setDownloadOriginal(true);

        expect(service.getDownloadQuality(), StreamingQuality.high);
        expect(service.getDownloadOriginal(), isTrue);
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

      expect(service.getDownloadQuality(), StreamingQuality.high);
      expect(service.getDownloadOriginal(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('quality_settings');
      expect(jsonString, isNotNull);
      final savedSettings = jsonDecode(jsonString!) as Map<String, dynamic>;
      expect(savedSettings['downloadQuality'], 'high');
      expect(savedSettings['downloadOriginal'], isTrue);
    });

    test('setDownloadQualityOption sets all 4 qualities correctly', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = QualitySettingsService();
      await service.initialize();

      // Original
      await service.setDownloadQualityOption(DownloadQuality.original);
      expect(service.getEffectiveDownloadQuality(), DownloadQuality.original);
      expect(service.getDownloadOriginal(), isTrue);
      expect(service.getDownloadQuality(), StreamingQuality.high);

      // High
      await service.setDownloadQualityOption(DownloadQuality.high);
      expect(service.getEffectiveDownloadQuality(), DownloadQuality.high);
      expect(service.getDownloadOriginal(), isFalse);
      expect(service.getDownloadQuality(), StreamingQuality.high);

      // Medium
      await service.setDownloadQualityOption(DownloadQuality.medium);
      expect(service.getEffectiveDownloadQuality(), DownloadQuality.medium);
      expect(service.getDownloadOriginal(), isFalse);
      expect(service.getDownloadQuality(), StreamingQuality.medium);

      // Low
      await service.setDownloadQualityOption(DownloadQuality.low);
      expect(service.getEffectiveDownloadQuality(), DownloadQuality.low);
      expect(service.getDownloadOriginal(), isFalse);
      expect(service.getDownloadQuality(), StreamingQuality.low);
    });

    test('QualitySettings fromJson handles original downloadQuality', () {
      final settings = QualitySettings.fromJson(<String, dynamic>{
        'downloadQuality': 'original',
      });
      expect(settings.effectiveDownloadQuality, DownloadQuality.original);
      expect(settings.downloadOriginal, isTrue);
      expect(settings.downloadQuality, StreamingQuality.high);
    });

    test('QualitySettings fromJson handles effectiveDownloadQuality key', () {
      final settings = QualitySettings.fromJson(<String, dynamic>{
        'effectiveDownloadQuality': 'low',
        'downloadQuality': 'high',
        'downloadOriginal': false,
      });
      expect(settings.effectiveDownloadQuality, DownloadQuality.low);
      expect(settings.downloadOriginal, isFalse);
      expect(settings.downloadQuality, StreamingQuality.low);
    });

    test('QualitySettings toJson includes effectiveDownloadQuality', () {
      const settings = QualitySettings(
        downloadQuality: StreamingQuality.medium,
        downloadOriginal: false,
      );
      final json = settings.toJson();
      expect(json['effectiveDownloadQuality'], 'medium');
      expect(json['downloadQuality'], 'medium');
      expect(json['downloadOriginal'], isFalse);
    });

    test('QualitySettings copyWith with effectiveDownloadQuality updates both fields', () {
      const initial = QualitySettings(
        downloadQuality: StreamingQuality.high,
        downloadOriginal: true,
      );
      final updated = initial.copyWith(effectiveDownloadQuality: DownloadQuality.low);
      expect(updated.effectiveDownloadQuality, DownloadQuality.low);
      expect(updated.downloadOriginal, isFalse);
      expect(updated.downloadQuality, StreamingQuality.low);
    });
  });

  group('speculative media transfer policy', () {
    test('allows background whole-file transfers only on Wi-Fi', () {
      expect(allowsSpeculativeMediaDownloadsFor(NetworkType.wifi), isTrue);
      expect(allowsSpeculativeMediaDownloadsFor(NetworkType.mobile), isFalse);
      expect(allowsSpeculativeMediaDownloadsFor(NetworkType.none), isFalse);
    });
  });
}
