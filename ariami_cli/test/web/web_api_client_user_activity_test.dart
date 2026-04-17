import 'dart:convert';

import 'package:ariami_cli/web/services/web_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('WebApiClient user activity', () {
    test('getUserActivity parses rows and includes device identity', () async {
      late Uri requestedUri;
      late Map<String, String> requestHeaders;

      final apiClient = WebApiClient(
        httpClient: MockClient((request) async {
          requestedUri = request.url;
          requestHeaders = request.headers;
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'userId': 'u1',
                  'username': 'alex',
                  'isDownloading': true,
                  'isTranscoding': true,
                  'activeDownloads': 2,
                  'queuedDownloads': 1,
                  'inFlightDownloadTranscodes': 1,
                },
              ],
              'generatedAt': DateTime.now().toUtc().toIso8601String(),
            }),
            200,
          );
        }),
        tokenProvider: () async => 'token-123',
        deviceIdProvider: () async => 'device-123',
        deviceName: 'Ariami CLI Web Dashboard',
      );

      final rows = await apiClient.getUserActivity();
      expect(rows, hasLength(1));
      expect(rows.first.userId, equals('u1'));
      expect(rows.first.username, equals('alex'));
      expect(rows.first.activeDownloads, equals(2));
      expect(rows.first.queuedDownloads, equals(1));
      expect(rows.first.inFlightDownloadTranscodes, equals(1));

      expect(requestedUri.path, equals('/api/admin/user-activity'));
      expect(requestedUri.queryParameters['deviceId'], equals('device-123'));
      expect(
        requestedUri.queryParameters['deviceName'],
        equals('Ariami CLI Web Dashboard'),
      );
      expect(requestHeaders['authorization'], equals('Bearer token-123'));
    });

    test('getUserActivity throws WebApiException on auth error', () async {
      final apiClient = WebApiClient(
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'AUTH_REQUIRED',
                'message': 'Authentication required',
              }
            }),
            401,
          );
        }),
        tokenProvider: () async => 'token-123',
        deviceIdProvider: () async => 'device-123',
      );

      try {
        await apiClient.getUserActivity();
        fail('Expected WebApiException');
      } on WebApiException catch (error) {
        expect(error.isAuthError, isTrue);
      }
    });
  });
}
