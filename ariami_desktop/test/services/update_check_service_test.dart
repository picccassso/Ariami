import 'package:ariami_desktop/services/update_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateCheckService.isNewerVersion', () {
    test('detects newer patch, minor, and major versions', () {
      expect(UpdateCheckService.isNewerVersion('4.4.1', than: '4.4.0'), isTrue);
      expect(UpdateCheckService.isNewerVersion('4.5.0', than: '4.4.0'), isTrue);
      expect(UpdateCheckService.isNewerVersion('9.0.0', than: '4.4.0'), isTrue);
    });

    test('rejects equal and older versions', () {
      expect(
          UpdateCheckService.isNewerVersion('4.4.0', than: '4.4.0'), isFalse);
      expect(
          UpdateCheckService.isNewerVersion('4.3.9', than: '4.4.0'), isFalse);
      expect(
          UpdateCheckService.isNewerVersion('3.9.9', than: '4.4.0'), isFalse);
    });

    test('handles versions with different segment counts', () {
      expect(UpdateCheckService.isNewerVersion('4.5', than: '4.4.0'), isTrue);
      expect(
          UpdateCheckService.isNewerVersion('4.4', than: '4.4.0'), isFalse);
      expect(
          UpdateCheckService.isNewerVersion('4.4.0.1', than: '4.4.0'), isTrue);
    });

    test('ignores build metadata and pre-release suffixes', () {
      expect(
          UpdateCheckService.isNewerVersion('4.4.0+9', than: '4.4.0'), isFalse);
      expect(UpdateCheckService.isNewerVersion('4.5.0-beta', than: '4.4.0'),
          isTrue);
    });

    test('treats malformed versions as not newer', () {
      expect(UpdateCheckService.isNewerVersion('latest', than: '4.4.0'),
          isFalse);
      expect(UpdateCheckService.isNewerVersion('', than: '4.4.0'), isFalse);
    });
  });
}
