import 'package:ariami_desktop/services/desktop_download_limits_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopDownloadLimitsService', () {
    test('returns macOS desktop limits on macOS', () async {
      final limits = await DesktopDownloadLimitsService.resolve(
        isMacOS: true,
        isLinux: false,
      );

      expect(limits.maxConcurrent, 30);
      expect(limits.maxQueue, 400);
      expect(limits.maxConcurrentPerUser, 10);
      expect(limits.maxQueuePerUser, 200);
    });

    test('returns default linux limits when Pi 5 is not detected', () async {
      final limits = await DesktopDownloadLimitsService.resolve(
        isMacOS: false,
        isLinux: true,
        readFile: (_) async => null,
      );

      expect(limits.maxConcurrent, 10);
      expect(limits.maxQueue, 120);
      expect(limits.maxConcurrentPerUser, 3);
      expect(limits.maxQueuePerUser, 50);
    });

    test('returns Pi 5 limits when Pi 5 model is detected', () async {
      final limits = await DesktopDownloadLimitsService.resolve(
        isMacOS: false,
        isLinux: true,
        readFile: (path) async {
          if (path == '/proc/device-tree/model') {
            return 'Raspberry Pi 5 Model B Rev 1.0';
          }
          return null;
        },
      );

      expect(limits.maxConcurrent, 10);
      expect(limits.maxQueue, 120);
      expect(limits.maxConcurrentPerUser, 6);
      expect(limits.maxQueuePerUser, 50);
    });
  });
}
