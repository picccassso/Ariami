import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';

import '../models/admin_credentials.dart';
import '../models/connected_client_row.dart';
import '../models/dashboard_http_response.dart';

/// Admin HTTP client for the desktop dashboard (login, kick, change password, heartbeat).
class DashboardAdminApiService {
  DashboardAdminApiService({
    required this.httpServer,
    required this.promptCredentials,
    required this.showMessage,
    required this.isMounted,
    this.onSessionInvalidated,
  });

  final AriamiHttpServer httpServer;
  final Future<AdminCredentials?> Function() promptCredentials;
  final void Function(String message, {bool isError}) showMessage;
  final bool Function() isMounted;
  final Future<void> Function()? onSessionInvalidated;

  String? _adminSessionToken;

  String? get adminSessionToken => _adminSessionToken;

  void clearAdminSessionToken() => _adminSessionToken = null;

  Uri _buildApiUri(
    String path, {
    bool includeDashboardDeviceIdentity = false,
  }) {
    final info = httpServer.getServerInfo();
    final host = (info['server'] as String?) ?? '127.0.0.1';
    final port = info['port'] as int? ?? 8080;
    final uri = Uri.parse('http://$host:$port$path');
    if (!includeDashboardDeviceIdentity) {
      return uri;
    }

    final queryParams = <String, String>{...uri.queryParameters};
    queryParams.putIfAbsent(
        'deviceId', () => DashboardClientIds.dashboardAdminDeviceId);
    queryParams.putIfAbsent(
        'deviceName', () => DashboardClientIds.dashboardAdminDeviceName);
    return uri.replace(queryParameters: queryParams);
  }

  Future<DashboardHttpResponse> sendApiRequest({
    required String method,
    required String path,
    String? bearerToken,
    Map<String, dynamic>? body,
    bool includeDashboardDeviceIdentity = false,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        _buildApiUri(
          path,
          includeDashboardDeviceIdentity: includeDashboardDeviceIdentity,
        ),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.set(
            HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      }
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();

      Map<String, dynamic>? jsonBody;
      if (responseBody.isNotEmpty) {
        try {
          final decoded = jsonDecode(responseBody);
          if (decoded is Map<String, dynamic>) {
            jsonBody = decoded;
          }
        } catch (_) {}
      }

      return DashboardHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        jsonBody: jsonBody,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> ensureAdminSessionToken({bool forcePrompt = false}) async {
    if (!forcePrompt &&
        _adminSessionToken != null &&
        _adminSessionToken!.isNotEmpty) {
      return _adminSessionToken;
    }

    if (!httpServer.isRunning) {
      if (isMounted()) {
        showMessage('Server is not running');
      }
      return null;
    }

    final credentials = await promptCredentials();
    if (credentials == null) return null;

    try {
      final response = await sendApiRequest(
        method: 'POST',
        path: '/api/auth/login',
        body: <String, dynamic>{
          'username': credentials.username,
          'password': credentials.password,
          'deviceId': DashboardClientIds.dashboardAdminDeviceId,
          'deviceName': DashboardClientIds.dashboardAdminDeviceName,
        },
      );

      if (!response.isSuccess) {
        if (isMounted()) {
          showMessage(response.errorMessage ?? 'Admin login failed',
              isError: true);
        }
        return null;
      }

      final token = response.jsonBody?['sessionToken'] as String?;
      if (token == null || token.isEmpty) {
        if (isMounted()) {
          showMessage('Admin login failed: missing session token', isError: true);
        }
        return null;
      }

      _adminSessionToken = token;
      unawaited(sendAdminHeartbeat());
      return token;
    } catch (e) {
      if (isMounted()) {
        showMessage('Admin login error: $e', isError: true);
      }
      return null;
    }
  }

  Future<DashboardHttpResponse?> sendAdminRequest({
    required String path,
    required Map<String, dynamic> body,
  }) async {
    var token = await ensureAdminSessionToken();
    if (token == null) return null;

    var response = await sendApiRequest(
      method: 'POST',
      path: path,
      bearerToken: token,
      body: body,
      includeDashboardDeviceIdentity: true,
    );

    if (response.statusCode == 401) {
      _adminSessionToken = null;
      token = await ensureAdminSessionToken(forcePrompt: true);
      if (token == null) return null;
      response = await sendApiRequest(
        method: 'POST',
        path: path,
        bearerToken: token,
        body: body,
        includeDashboardDeviceIdentity: true,
      );
    }

    return response;
  }

  Future<void> sendAdminHeartbeat() async {
    if (!isMounted() || !httpServer.isRunning) return;
    final token = _adminSessionToken;
    if (token == null || token.isEmpty) return;

    try {
      final response = await sendApiRequest(
        method: 'GET',
        path: '/api/me',
        bearerToken: token,
        includeDashboardDeviceIdentity: true,
      );
      if (response.statusCode == 401) {
        _adminSessionToken = null;
        httpServer.connectionManager
            .unregisterClient(DashboardClientIds.dashboardAdminDeviceId);
        if (onSessionInvalidated != null) {
          await onSessionInvalidated!();
        }
      }
    } catch (_) {
      // Ignore transient heartbeat failures.
    }
  }
}
