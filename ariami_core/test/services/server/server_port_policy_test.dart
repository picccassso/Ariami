import 'dart:io';

import 'package:ariami_core/services/server/server_port_policy.dart';
import 'package:test/test.dart';

void main() {
  group('ServerPortPolicy.buildCandidates', () {
    test('returns only preferred port when fallback disabled', () {
      expect(
        ServerPortPolicy.buildCandidates(
          preferredPort: 9000,
          savedPort: 8081,
          allowFallback: false,
        ),
        [9000],
      );
    });

    test('orders saved port before preferred then scan range', () {
      final candidates = ServerPortPolicy.buildCandidates(
        preferredPort: 8080,
        savedPort: 8081,
      );
      expect(candidates.take(2), [8081, 8080]);
      expect(candidates.length, 20);
      expect(candidates.last, 8099);
    });

    test('deduplicates when saved equals preferred', () {
      final candidates = ServerPortPolicy.buildCandidates(
        preferredPort: 8080,
        savedPort: 8080,
      );
      expect(candidates.where((port) => port == 8080).length, 1);
      expect(candidates.first, 8080);
    });

    test('includes full fallback range when no saved port', () {
      final candidates = ServerPortPolicy.buildCandidates(
        preferredPort: 8080,
      );
      expect(candidates.first, 8080);
      expect(candidates.last, 8099);
      expect(candidates.length, 20);
    });
  });

  group('ServerPortPolicy.isAddressInUseError', () {
    test('detects address already in use text', () {
      expect(
        ServerPortPolicy.isAddressInUseError(
          SocketException('Address already in use, port = 8080'),
        ),
        isTrue,
      );
    });

    test('detects generic SocketException bind failures', () {
      expect(
        ServerPortPolicy.isAddressInUseError(
          const SocketException('Failed to create server socket'),
        ),
        isTrue,
      );
    });

    test('returns false for unrelated errors', () {
      expect(
        ServerPortPolicy.isAddressInUseError(StateError('bad config')),
        isFalse,
      );
    });
  });

  group('ServerPortPolicy.formatFallbackMessage', () {
    test('returns null when ports match', () {
      expect(
        ServerPortPolicy.formatFallbackMessage(
          attemptedPort: 8080,
          actualPort: 8080,
        ),
        isNull,
      );
    });

    test('returns user-facing message when fallback used', () {
      expect(
        ServerPortPolicy.formatFallbackMessage(
          attemptedPort: 8080,
          actualPort: 8081,
        ),
        'Port 8080 was in use, so Ariami started on 8081.',
      );
    });
  });

  group('PortBindingException', () {
    test('explicit port message mentions --port', () {
      final error = PortBindingException(
        preferredPort: 9000,
        candidates: [9000],
        explicitPort: true,
      );
      expect(error.toString(), contains('9000'));
      expect(error.toString(), contains('--port'));
    });

    test('fallback exhaustion message mentions range', () {
      final error = PortBindingException(
        preferredPort: 8080,
        candidates: [8080, 8081],
      );
      expect(error.toString(), contains('8080'));
      expect(error.toString(), contains('8099'));
    });
  });
}
