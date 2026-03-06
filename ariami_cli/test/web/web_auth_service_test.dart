import 'dart:convert';

import 'package:ariami_cli/web/services/web_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final deviceIdPattern = RegExp(r'^cli_web_\d+_[0-9a-f]{16}$');

  group('WebAuthService', () {
    test('getOrCreateDeviceId persists stable id', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = WebAuthService(
        httpClient: MockClient((_) async {
          return http.Response('{}', 200);
        }),
      );

      final first = await service.getOrCreateDeviceId();
      final second = await service.getOrCreateDeviceId();

      expect(first, isNotEmpty);
      expect(first, matches(deviceIdPattern));
      expect(second, equals(first));
    });

    test('login stores session token on success', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = WebAuthService(
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/auth/login') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['username'], equals('alex'));
            expect(body['password'], equals('pw'));
            expect(body['deviceId'], matches(deviceIdPattern));
            expect(body['deviceName'], isNotEmpty);
            return http.Response(
              jsonEncode(<String, dynamic>{
                'sessionToken': 'token-123',
                'userId': 'u-1',
                'username': 'alex',
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final response = await service.login(
        username: 'alex',
        password: 'pw',
      );

      expect(response.isSuccess, isTrue);
      expect(await service.getSessionToken(), equals('token-123'));
      expect(await service.hasSessionToken(), isTrue);
    });
  });
}
