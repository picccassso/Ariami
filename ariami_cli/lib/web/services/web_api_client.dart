import 'dart:convert';

import 'package:ariami_core/models/auth_models.dart';
import 'package:http/http.dart' as http;

typedef WebSessionTokenProvider = Future<String?> Function();

class WebApiResponse {
  const WebApiResponse({
    required this.statusCode,
    required this.body,
    this.jsonBody,
  });

  final int statusCode;
  final String body;
  final Map<String, dynamic>? jsonBody;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  String? get errorCode {
    final error = jsonBody?['error'];
    if (error is Map<String, dynamic>) {
      return error['code'] as String?;
    }
    return null;
  }

  String? get errorMessage {
    final error = jsonBody?['error'];
    if (error is Map<String, dynamic>) {
      return error['message'] as String?;
    }
    return null;
  }

  bool get isAuthError =>
      errorCode == AuthErrorCodes.authRequired ||
      errorCode == AuthErrorCodes.sessionExpired;
}

class ConnectedClientRow {
  const ConnectedClientRow({
    required this.deviceId,
    required this.deviceName,
    this.clientType,
    this.userId,
    this.username,
    this.connectedAt,
    this.lastHeartbeat,
  });

  final String deviceId;
  final String deviceName;
  final String? clientType;
  final String? userId;
  final String? username;
  final DateTime? connectedAt;
  final DateTime? lastHeartbeat;

  factory ConnectedClientRow.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.tryParse(value)?.toLocal();
    }

    return ConnectedClientRow(
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Unknown Device',
      clientType: json['clientType'] as String?,
      userId: json['userId'] as String?,
      username: json['username'] as String?,
      connectedAt: parseDate(json['connectedAt']),
      lastHeartbeat: parseDate(json['lastHeartbeat']),
    );
  }
}

class UserActivityRow {
  const UserActivityRow({
    required this.userId,
    required this.username,
    required this.isDownloading,
    required this.isTranscoding,
    required this.activeDownloads,
    required this.queuedDownloads,
    required this.inFlightDownloadTranscodes,
  });

  final String userId;
  final String username;
  final bool isDownloading;
  final bool isTranscoding;
  final int activeDownloads;
  final int queuedDownloads;
  final int inFlightDownloadTranscodes;

  factory UserActivityRow.fromJson(Map<String, dynamic> json) {
    return UserActivityRow(
      userId: json['userId'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown User',
      isDownloading: json['isDownloading'] as bool? ?? false,
      isTranscoding: json['isTranscoding'] as bool? ?? false,
      activeDownloads: json['activeDownloads'] as int? ?? 0,
      queuedDownloads: json['queuedDownloads'] as int? ?? 0,
      inFlightDownloadTranscodes:
          json['inFlightDownloadTranscodes'] as int? ?? 0,
    );
  }
}

class WebApiClient {
  WebApiClient({
    http.Client? httpClient,
    this.tokenProvider,
    this.deviceIdProvider,
    this.deviceName,
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final WebSessionTokenProvider? tokenProvider;
  final Future<String> Function()? deviceIdProvider;
  final String? deviceName;

  Future<WebApiResponse> get(
    String path, {
    Map<String, String>? headers,
    bool includeAuth = true,
    bool includeDeviceIdentity = false,
  }) {
    return _send(
      method: 'GET',
      path: path,
      headers: headers,
      includeAuth: includeAuth,
      includeDeviceIdentity: includeDeviceIdentity,
    );
  }

  Future<WebApiResponse> post(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    bool includeAuth = true,
    bool includeDeviceIdentity = false,
  }) {
    return _send(
      method: 'POST',
      path: path,
      headers: headers,
      body: body,
      includeAuth: includeAuth,
      includeDeviceIdentity: includeDeviceIdentity,
    );
  }

  Future<List<ConnectedClientRow>> getConnectedClients() async {
    final response = await get(
      '/api/admin/connected-clients',
      includeDeviceIdentity: true,
    );
    if (!response.isSuccess) {
      throw WebApiException(response);
    }

    final rows = response.jsonBody?['clients'];
    if (rows is! List) {
      return const <ConnectedClientRow>[];
    }

    return rows
        .whereType<Map<String, dynamic>>()
        .map(ConnectedClientRow.fromJson)
        .toList();
  }

  Future<void> kickClient(String deviceId) async {
    final response = await post(
      '/api/admin/kick-client',
      body: <String, dynamic>{'deviceId': deviceId},
      includeDeviceIdentity: true,
    );
    if (!response.isSuccess) {
      throw WebApiException(response);
    }
  }

  Future<void> changePassword({
    required String username,
    required String newPassword,
  }) async {
    final response = await post(
      '/api/admin/change-password',
      body: <String, dynamic>{
        'username': username,
        'newPassword': newPassword,
      },
      includeDeviceIdentity: true,
    );
    if (!response.isSuccess) {
      throw WebApiException(response);
    }
  }

  Future<List<UserActivityRow>> getUserActivity() async {
    final response = await get(
      '/api/admin/user-activity',
      includeDeviceIdentity: true,
    );
    if (!response.isSuccess) {
      throw WebApiException(response);
    }

    final rows = response.jsonBody?['users'];
    if (rows is! List) {
      return const <UserActivityRow>[];
    }

    return rows
        .whereType<Map<String, dynamic>>()
        .map(UserActivityRow.fromJson)
        .toList();
  }

  Future<WebApiResponse> _send({
    required String method,
    required String path,
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    required bool includeAuth,
    required bool includeDeviceIdentity,
  }) async {
    final requestHeaders = <String, String>{
      if (headers != null) ...headers,
    };

    if (body != null && !requestHeaders.containsKey('Content-Type')) {
      requestHeaders['Content-Type'] = 'application/json';
    }

    if (includeAuth && tokenProvider != null) {
      final token = await tokenProvider!.call();
      if (token != null && token.isNotEmpty) {
        requestHeaders['Authorization'] = 'Bearer $token';
      }
    }

    var uri = Uri.parse(path);
    if (includeDeviceIdentity && deviceIdProvider != null) {
      final providedDeviceId = await deviceIdProvider!.call();
      if (providedDeviceId.isNotEmpty) {
        uri = _withDeviceIdentity(
          uri,
          deviceId: providedDeviceId,
          deviceName: deviceName,
        );
      }
    }
    late final http.Response response;
    if (method == 'GET') {
      response = await _httpClient.get(uri, headers: requestHeaders);
    } else if (method == 'POST') {
      response = await _httpClient.post(
        uri,
        headers: requestHeaders,
        body: body == null ? null : jsonEncode(body),
      );
    } else {
      throw UnsupportedError('Unsupported HTTP method: $method');
    }

    Map<String, dynamic>? jsonBody;
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          jsonBody = decoded;
        }
      } catch (_) {
        // Non-JSON response body; keep as plain text.
      }
    }

    return WebApiResponse(
      statusCode: response.statusCode,
      body: response.body,
      jsonBody: jsonBody,
    );
  }

  Uri _withDeviceIdentity(
    Uri uri, {
    required String deviceId,
    String? deviceName,
  }) {
    final queryParams = <String, String>{...uri.queryParameters};
    queryParams.putIfAbsent('deviceId', () => deviceId);
    if (deviceName != null && deviceName.isNotEmpty) {
      queryParams.putIfAbsent('deviceName', () => deviceName);
    }
    return uri.replace(queryParameters: queryParams);
  }
}

class WebApiException implements Exception {
  const WebApiException(this.response);

  final WebApiResponse response;

  String get code => response.errorCode ?? 'REQUEST_FAILED';
  String get message =>
      response.errorMessage ??
      'Request failed with status ${response.statusCode}.';

  bool get isAuthError => response.isAuthError;
  bool get isForbidden => response.statusCode == 403;

  @override
  String toString() => 'WebApiException($code): $message';
}
