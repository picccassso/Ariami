import 'dart:convert';

import 'package:ariami_cli/web/services/web_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dashboard auth flow contract', () {
    test('stats auth failure is detectable for login redirect', () async {
      final apiClient = WebApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/stats') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'error': <String, dynamic>{
                  'code': 'AUTH_REQUIRED',
                  'message': 'Authentication required',
                },
              }),
              401,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final response = await apiClient.get('/api/stats');
      expect(response.statusCode, 401);
      expect(response.isAuthError, isTrue);
    });

    test('bearer auth is attached for protected stats call', () async {
      String? capturedAuthHeader;
      final apiClient = WebApiClient(
        tokenProvider: () async => 'session-token',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/stats') {
            capturedAuthHeader = request.headers['authorization'];
            return http.Response(
              jsonEncode(<String, dynamic>{'songCount': 1}),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final response = await apiClient.get('/api/stats');
      expect(response.statusCode, 200);
      expect(capturedAuthHeader, equals('Bearer session-token'));
      expect(response.isAuthError, isFalse);
    });

    test('connected-clients requests include dashboard device identity', () async {
      String? capturedDeviceId;
      String? capturedDeviceName;

      final apiClient = WebApiClient(
        tokenProvider: () async => 'session-token',
        deviceIdProvider: () async => 'dashboard-device',
        deviceName: 'Dashboard Control',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/admin/connected-clients') {
            capturedDeviceId = request.url.queryParameters['deviceId'];
            capturedDeviceName = request.url.queryParameters['deviceName'];
            return http.Response(
              jsonEncode(<String, dynamic>{
                'clients': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'deviceId': 'dashboard-device',
                    'deviceName': 'Dashboard Control',
                    'clientType': 'dashboard_admin',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final rows = await apiClient.getConnectedClients();
      expect(capturedDeviceId, equals('dashboard-device'));
      expect(capturedDeviceName, equals('Dashboard Control'));
      expect(rows.length, equals(1));
      expect(rows.first.clientType, equals('dashboard_admin'));
    });

    test(
        'kick-client and change-password include dashboard device identity on admin actions',
        () async {
      final capturedPaths = <String>[];
      final capturedDeviceIds = <String?>[];
      final capturedDeviceNames = <String?>[];

      final apiClient = WebApiClient(
        tokenProvider: () async => 'session-token',
        deviceIdProvider: () async => 'dashboard-device',
        deviceName: 'Dashboard Control',
        httpClient: MockClient((request) async {
          capturedPaths.add(request.url.path);
          capturedDeviceIds.add(request.url.queryParameters['deviceId']);
          capturedDeviceNames.add(request.url.queryParameters['deviceName']);

          if (request.url.path == '/api/admin/kick-client') {
            return http.Response(
              jsonEncode(<String, dynamic>{'status': 'kicked'}),
              200,
            );
          }
          if (request.url.path == '/api/admin/change-password') {
            return http.Response(
              jsonEncode(<String, dynamic>{'status': 'password_changed'}),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      await apiClient.kickClient('target-device');
      await apiClient.changePassword(
        username: 'target-user',
        newPassword: 'new-password',
      );

      expect(
        capturedPaths,
        equals(<String>[
          '/api/admin/kick-client',
          '/api/admin/change-password',
        ]),
      );
      expect(capturedDeviceIds, everyElement(equals('dashboard-device')));
      expect(capturedDeviceNames, everyElement(equals('Dashboard Control')));
    });
  });
}
