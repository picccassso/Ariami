import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'web_api_client.dart';

typedef SharedPreferencesLoader = Future<SharedPreferences> Function();

class WebAuthService {
  WebAuthService({
    http.Client? httpClient,
    SharedPreferencesLoader? preferencesLoader,
  })  : _httpClient = httpClient ?? http.Client(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const String _sessionTokenKey = 'cli_web_session_token';
  static const String _deviceIdKey = 'cli_web_device_id';
  static const String _defaultDeviceName = 'Ariami CLI Web Dashboard';

  final http.Client _httpClient;
  final SharedPreferencesLoader _preferencesLoader;
  final Random _secureRandom = Random.secure();

  Future<WebApiResponse> register({
    required String username,
    required String password,
  }) async {
    final apiClient = WebApiClient(httpClient: _httpClient);
    return apiClient.post(
      '/api/auth/register',
      includeAuth: false,
      body: <String, dynamic>{
        'username': username,
        'password': password,
      },
    );
  }

  Future<WebApiResponse> login({
    required String username,
    required String password,
    String deviceName = _defaultDeviceName,
  }) async {
    final deviceId = await getOrCreateDeviceId();
    final apiClient = WebApiClient(httpClient: _httpClient);
    final response = await apiClient.post(
      '/api/auth/login',
      includeAuth: false,
      body: <String, dynamic>{
        'username': username,
        'password': password,
        'deviceId': deviceId,
        'deviceName': deviceName,
      },
    );

    if (response.isSuccess) {
      final token = response.jsonBody?['sessionToken'] as String?;
      if (token != null && token.isNotEmpty) {
        await _saveSessionToken(token);
      }
    }

    return response;
  }

  Future<WebApiResponse> logout() async {
    final apiClient = WebApiClient(
      httpClient: _httpClient,
      tokenProvider: getSessionToken,
    );
    final response = await apiClient.post('/api/auth/logout');
    if (response.isSuccess || response.isAuthError) {
      await clearSessionToken();
    }
    return response;
  }

  Future<WebApiResponse> me() async {
    final apiClient = WebApiClient(
      httpClient: _httpClient,
      tokenProvider: getSessionToken,
    );
    return apiClient.get('/api/me');
  }

  Future<bool> hasSessionToken() async {
    final token = await getSessionToken();
    return token != null && token.isNotEmpty;
  }

  Future<String?> getSessionToken() async {
    final prefs = await _preferencesLoader();
    return prefs.getString(_sessionTokenKey);
  }

  Future<void> clearSessionToken() async {
    final prefs = await _preferencesLoader();
    await prefs.remove(_sessionTokenKey);
  }

  Future<String> getOrCreateDeviceId() async {
    final prefs = await _preferencesLoader();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final nonce = _generateHexNonce(8);
    final generated = 'cli_web_${DateTime.now().millisecondsSinceEpoch}_$nonce';
    await prefs.setString(_deviceIdKey, generated);
    return generated;
  }

  String _generateHexNonce(int byteCount) {
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      final byte = _secureRandom.nextInt(256);
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Future<void> _saveSessionToken(String token) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(_sessionTokenKey, token);
  }
}
