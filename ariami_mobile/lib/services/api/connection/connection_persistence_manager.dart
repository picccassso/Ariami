import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/server_info.dart';

/// Manages persistence of connection-related data.
///
/// Handles:
/// - Server info storage (SharedPreferences)
/// - Session ID storage (SharedPreferences)
/// - Auth token storage (FlutterSecureStorage)
/// - Device ID storage (SharedPreferences)
class ConnectionPersistenceManager {
  static const String _serverInfoKey = 'server_info';
  static const String _sessionIdKey = 'session_id';
  static const String _sessionTokenKey = 'session_token';
  static const String _userIdKey = 'user_id';
  static const String _usernameKey = 'username';
  static const String _deviceIdKey = 'device_id';

  final SharedPreferences? _prefs;
  final FlutterSecureStorage? _secureStorage;

  /// Creates a ConnectionPersistenceManager.
  ///
  /// If [prefs] or [secureStorage] are provided, they will be used.
  /// Otherwise, new instances will be created on each operation.
  ConnectionPersistenceManager({
    SharedPreferences? prefs,
    FlutterSecureStorage? secureStorage,
  })  : _prefs = prefs,
        _secureStorage = secureStorage;

  // ============================================================================
  // Server Info Persistence
  // ============================================================================

  /// Save server info and session ID to SharedPreferences.
  Future<void> saveConnectionInfo(
    ServerInfo serverInfo,
    String sessionId,
  ) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(
      _serverInfoKey,
      const JsonEncoder().convert(serverInfo.toJson()),
    );
    await prefs.setString(_sessionIdKey, sessionId);
  }

  /// Load server info from SharedPreferences.
  ///
  /// Returns null if no server info is stored or if parsing fails.
  Future<ServerInfo?> loadServerInfo() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final serverJson = prefs.getString(_serverInfoKey);

    if (serverJson == null) {
      return null;
    }

    try {
      return ServerInfo.fromJson(
        Map<String, dynamic>.from(
          const JsonDecoder().convert(serverJson) as Map,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// Load session ID from SharedPreferences.
  ///
  /// Returns null if no session ID is stored.
  Future<String?> loadSessionId() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.getString(_sessionIdKey);
  }

  /// Clear connection info from SharedPreferences.
  Future<void> clearConnectionInfo() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.remove(_serverInfoKey);
    await prefs.remove(_sessionIdKey);
  }

  // ============================================================================
  // Auth Persistence (Secure Storage)
  // ============================================================================

  /// Save auth info to secure storage.
  Future<void> saveAuthInfo({
    required String sessionToken,
    required String userId,
    required String username,
  }) async {
    final storage = _secureStorage ?? const FlutterSecureStorage();
    await storage.write(key: _sessionTokenKey, value: sessionToken);
    await storage.write(key: _userIdKey, value: userId);
    await storage.write(key: _usernameKey, value: username);
  }

  /// Load auth info from secure storage.
  ///
  /// Returns a map with keys 'sessionToken', 'userId', and 'username'.
  /// Values may be null if not found.
  Future<Map<String, String?>> loadAuthInfo() async {
    final storage = _secureStorage ?? const FlutterSecureStorage();
    return {
      'sessionToken': await storage.read(key: _sessionTokenKey),
      'userId': await storage.read(key: _userIdKey),
      'username': await storage.read(key: _usernameKey),
    };
  }

  /// Clear all auth info from secure storage.
  Future<void> clearAuthInfo() async {
    final storage = _secureStorage ?? const FlutterSecureStorage();
    await storage.delete(key: _sessionTokenKey);
    await storage.delete(key: _userIdKey);
    await storage.delete(key: _usernameKey);
  }

  /// Save only the session token.
  Future<void> saveSessionToken(String token) async {
    final storage = _secureStorage ?? const FlutterSecureStorage();
    await storage.write(key: _sessionTokenKey, value: token);
  }

  /// Load only the session token.
  Future<String?> loadSessionToken() async {
    final storage = _secureStorage ?? const FlutterSecureStorage();
    return storage.read(key: _sessionTokenKey);
  }

  // ============================================================================
  // Device ID Persistence
  // ============================================================================

  /// Save device ID to SharedPreferences.
  Future<void> saveDeviceId(String deviceId) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, deviceId);
  }

  /// Load device ID from SharedPreferences.
  ///
  /// Returns null if no device ID is stored.
  Future<String?> loadDeviceId() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.getString(_deviceIdKey);
  }

  /// Clear device ID from SharedPreferences.
  Future<void> clearDeviceId() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
  }
}
