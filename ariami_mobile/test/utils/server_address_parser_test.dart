import 'package:ariami_mobile/utils/server_address_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ParsedServerAddress.tryParse', () {
    test('parses host with scheme and port', () {
      final result = ParsedServerAddress.tryParse('http://192.168.1.50:8080');
      expect(result, isNotNull);
      expect(result!.host, '192.168.1.50');
      expect(result.port, 8080);
    });

    test('parses host with port but no scheme', () {
      final result = ParsedServerAddress.tryParse('192.168.1.50:8080');
      expect(result, isNotNull);
      expect(result!.host, '192.168.1.50');
      expect(result.port, 8080);
    });

    test('parses Tailscale-style address with scheme', () {
      final result = ParsedServerAddress.tryParse('http://100.64.0.1:8080');
      expect(result, isNotNull);
      expect(result!.host, '100.64.0.1');
      expect(result.port, 8080);
    });

    test('parses Tailscale-style address without scheme', () {
      final result = ParsedServerAddress.tryParse('100.64.0.1:8080');
      expect(result, isNotNull);
      expect(result!.host, '100.64.0.1');
      expect(result.port, 8080);
    });

    test('defaults to port 8080 when omitted', () {
      final withScheme = ParsedServerAddress.tryParse('http://192.168.1.50');
      expect(withScheme, isNotNull);
      expect(withScheme!.host, '192.168.1.50');
      expect(withScheme.port, ParsedServerAddress.defaultPort);

      final withoutScheme = ParsedServerAddress.tryParse('192.168.1.50');
      expect(withoutScheme, isNotNull);
      expect(withoutScheme!.host, '192.168.1.50');
      expect(withoutScheme.port, 8080);
    });

    test('respects a non-default port', () {
      final result = ParsedServerAddress.tryParse('192.168.1.50:9090');
      expect(result, isNotNull);
      expect(result!.port, 9090);
    });

    test('trims surrounding whitespace', () {
      final result = ParsedServerAddress.tryParse('  192.168.1.50:8080  ');
      expect(result, isNotNull);
      expect(result!.host, '192.168.1.50');
      expect(result.port, 8080);
    });

    test('ignores trailing path and slash', () {
      final result = ParsedServerAddress.tryParse('http://192.168.1.50:8080/');
      expect(result, isNotNull);
      expect(result!.host, '192.168.1.50');
      expect(result.port, 8080);
    });

    test('parses a hostname', () {
      final result = ParsedServerAddress.tryParse('my-server.local:8080');
      expect(result, isNotNull);
      expect(result!.host, 'my-server.local');
      expect(result.port, 8080);
    });

    test('returns null for empty input', () {
      expect(ParsedServerAddress.tryParse(''), isNull);
      expect(ParsedServerAddress.tryParse('   '), isNull);
    });

    test('returns null when no host can be extracted', () {
      expect(ParsedServerAddress.tryParse(':8080'), isNull);
    });

    test('returns null for an out-of-range port', () {
      expect(ParsedServerAddress.tryParse('192.168.1.50:0'), isNull);
      expect(ParsedServerAddress.tryParse('192.168.1.50:70000'), isNull);
    });
  });
}
