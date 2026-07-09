import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/api/api_client.dart';
import 'package:ariami_mobile/utils/setup_error_messages.dart';

void main() {
  group('describeSetupConnectError', () {
    test('timeouts mention timing out and the address', () {
      final message = describeSetupConnectError(
        TimeoutException('x'),
        address: '192.168.1.50:8080',
      );
      expect(message, contains('timed out'));
      expect(message, contains('192.168.1.50:8080'));
    });

    test('wrapped timeout from ApiClient is still recognized', () {
      final error = ApiException(
        code: ApiErrorCodes.serverError,
        message:
            'Network error: TimeoutException after 0:00:10.000000: Future not completed',
      );
      expect(describeSetupConnectError(error), contains('timed out'));
    });

    test('connection refused maps to wrong-port guidance', () {
      final error = ApiException(
        code: ApiErrorCodes.serverError,
        message:
            'Network error: SocketException: Connection refused (OS Error: Connection refused, errno = 61)',
      );
      final message = describeSetupConnectError(error, address: 'pi:9999');
      expect(message, contains('Nothing is listening'));
      expect(message, contains('port'));
    });

    test('unreachable host maps to network guidance', () {
      final error = ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: SocketException: Failed host lookup: nope',
      );
      final message = describeSetupConnectError(error);
      expect(message, contains('same network or VPN'));
    });

    test('non-Ariami HTTP responder is called out', () {
      final error = ApiException(
        code: ApiErrorCodes.serverError,
        message: 'HTTP 404: Not Found',
      );
      final message = describeSetupConnectError(error, address: 'nas:8080');
      expect(message.toLowerCase(), contains('ariami server'));
    });

    test('rate limiting passes the server message through', () {
      final error = ApiException(
        code: ApiErrorCodes.rateLimited,
        message: 'Too many failed auth attempts. Try again in 5 minutes.',
      );
      expect(
        describeSetupConnectError(error),
        contains('Too many failed auth attempts'),
      );
    });

    test('never echoes credentials-like content for unknown errors', () {
      final message = describeSetupConnectError(Exception('boom'));
      expect(message, contains('try again'));
      expect(message, isNot(contains('boom')));
    });
  });
}
