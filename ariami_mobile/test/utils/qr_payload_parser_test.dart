import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ariami_mobile/utils/qr_payload_parser.dart';

Map<String, dynamic> _validPayload() => {
      'server': '100.64.0.5',
      'lanServer': '192.168.1.50',
      'port': 8080,
      'name': 'Alex\'s Mac',
      'version': '4.4.0',
      'authRequired': true,
      'legacyMode': false,
      'registrationToken': 'a1b2c3d4e5f60718293a4b5c6d7e8f90'
          'a1b2c3d4e5f60718293a4b5c6d7e8f90',
    };

void main() {
  group('QrPayloadParser', () {
    test('accepts a full valid payload', () {
      final result = QrPayloadParser.parse(jsonEncode(_validPayload()));

      expect(result.isValid, isTrue);
      final info = result.serverInfo!;
      expect(info.server, '100.64.0.5');
      expect(info.lanServer, '192.168.1.50');
      // tailscaleServer derived because lanServer differs from server.
      expect(info.tailscaleServer, '100.64.0.5');
      expect(info.port, 8080);
      expect(info.authRequired, isTrue);
      expect(info.legacyMode, isFalse);
      expect(info.registrationToken, isNotNull);
    });

    test('accepts a minimal payload without optional fields', () {
      final result = QrPayloadParser.parse(jsonEncode({
        'server': '192.168.1.50',
        'port': 8080,
        'name': 'Server',
        'version': '4.4.0',
      }));

      expect(result.isValid, isTrue);
      expect(result.serverInfo!.authRequired, isFalse);
      expect(result.serverInfo!.legacyMode, isTrue);
      expect(result.serverInfo!.registrationToken, isNull);
    });

    test('accepts an IPv6 host', () {
      final result = QrPayloadParser.parse(jsonEncode({
        'server': 'fd7a:115c:a1e0::1',
        'port': 8080,
        'name': 'Server',
        'version': '4.4.0',
      }));

      expect(result.isValid, isTrue);
    });

    group('rejects', () {
      void expectRejected(String raw) {
        final result = QrPayloadParser.parse(raw);
        expect(result.isValid, isFalse,
            reason:
                'should reject: ${raw.length > 60 ? raw.substring(0, 60) : raw}');
        expect(result.error, isNotNull);
        // Errors must never echo the scanned payload (it may hold a token).
        if (raw.trim().isNotEmpty) {
          expect(result.error, isNot(contains(raw.trim())));
        }
      }

      test('non-JSON text (URL, WiFi share codes...)', () {
        expectRejected('https://example.com/some/link');
        expectRejected('WIFI:T:WPA;S:MyNet;P:secret;;');
        expectRejected('');
        expectRejected('   ');
      });

      test('JSON that is not an object', () {
        expectRejected('[1,2,3]');
        expectRejected('"just a string"');
        expectRejected('42');
      });

      test('oversized payloads', () {
        final huge = jsonEncode({
          ..._validPayload(),
          'padding': 'x' * QrPayloadParser.maxPayloadLength,
        });
        expectRejected(huge);
      });

      test('missing or malformed host', () {
        expectRejected(jsonEncode({..._validPayload()}..remove('server')));
        expectRejected(jsonEncode({..._validPayload(), 'server': ''}));
        expectRejected(jsonEncode({..._validPayload(), 'server': 42}));
        expectRejected(jsonEncode(
            {..._validPayload(), 'server': 'http://192.168.1.50'}));
        expectRejected(
            jsonEncode({..._validPayload(), 'server': '192.168.1.50/path'}));
        expectRejected(
            jsonEncode({..._validPayload(), 'server': 'host name with space'}));
        expectRejected(
            jsonEncode({..._validPayload(), 'server': 'user@evil.com'}));
      });

      test('malformed optional endpoints', () {
        expectRejected(
            jsonEncode({..._validPayload(), 'lanServer': 'http://x'}));
        expectRejected(
            jsonEncode({..._validPayload(), 'tailscaleServer': 'a b'}));
      });

      test('invalid ports', () {
        expectRejected(jsonEncode({..._validPayload()}..remove('port')));
        expectRejected(jsonEncode({..._validPayload(), 'port': 0}));
        expectRejected(jsonEncode({..._validPayload(), 'port': 70000}));
        expectRejected(jsonEncode({..._validPayload(), 'port': '8080'}));
        expectRejected(jsonEncode({..._validPayload(), 'port': 8080.5}));
      });

      test('mistyped auth flags cannot downgrade routing', () {
        expectRejected(
            jsonEncode({..._validPayload(), 'authRequired': 'false'}));
        expectRejected(jsonEncode({..._validPayload(), 'legacyMode': 1}));
      });

      test('malformed registration tokens', () {
        expectRejected(
            jsonEncode({..._validPayload(), 'registrationToken': ''}));
        expectRejected(
            jsonEncode({..._validPayload(), 'registrationToken': 42}));
        expectRejected(jsonEncode(
            {..._validPayload(), 'registrationToken': 'has spaces'}));
        expectRejected(jsonEncode(
            {..._validPayload(), 'registrationToken': 'x' * 300}));
      });

      test('mistyped name/version/downloadLimits', () {
        expectRejected(jsonEncode({..._validPayload(), 'name': 42}));
        expectRejected(jsonEncode({..._validPayload(), 'version': false}));
        expectRejected(
            jsonEncode({..._validPayload(), 'downloadLimits': 'nope'}));
      });
    });

    test('caps absurdly long names instead of rejecting', () {
      final result = QrPayloadParser.parse(jsonEncode({
        ..._validPayload(),
        'name': 'N' * 500,
      }));

      expect(result.isValid, isTrue);
      expect(result.serverInfo!.name.length, lessThanOrEqualTo(120));
    });

    test('missing name falls back to the host', () {
      final result = QrPayloadParser.parse(jsonEncode({
        'server': '192.168.1.50',
        'port': 8080,
        'version': '4.4.0',
      }));

      expect(result.isValid, isTrue);
      expect(result.serverInfo!.name, '192.168.1.50');
    });
  });
}
