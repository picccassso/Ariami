import 'dart:io';

import 'package:ariami_cli/services/browser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowserService', () {
    test('returns false when opener exits non-zero', () async {
      final service = BrowserService(
        processRunner: (executable, arguments) async {
          return ProcessResult(0, 1, '', 'failed to open');
        },
      );

      final opened = await service.openUrl('http://localhost:8080');
      expect(opened, isFalse);
    });

    test('returns true when injected opener exits zero', () async {
      final service = BrowserService(
        processRunner: (executable, arguments) async {
          return ProcessResult(0, 0, '', '');
        },
      );

      final opened = await service.openUrl('http://localhost:8080');
      expect(opened, isTrue);
    });

    test('returns false when process runner throws', () async {
      final service = BrowserService(
        processRunner: (executable, arguments) async {
          throw ProcessException(executable, arguments, 'missing', 127);
        },
      );

      final opened = await service.openUrl('http://localhost:8080');
      expect(opened, isFalse);
    });

    test('headless linux returns false for default display check', () async {
      if (!Platform.isLinux) {
        return;
      }

      final service = BrowserService(hasDisplaySession: () => false);
      final opened = await service.openUrl('http://localhost:8080');
      expect(opened, isFalse);
    });

    test(
        'injected process runner is used even when display check would fail',
        () async {
      var runnerCalled = false;
      final service = BrowserService(
        hasDisplaySession: () => false,
        processRunner: (executable, arguments) async {
          runnerCalled = true;
          return ProcessResult(0, 0, '', '');
        },
      );

      final opened = await service.openUrl('http://localhost:8080');
      expect(opened, isTrue);
      expect(runnerCalled, isTrue);
    });
  });
}
