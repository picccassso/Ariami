import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage app-wide state and persistent data
/// Tracks setup completion, device info, and server connection history
class AppStateService extends ChangeNotifier {
  static const String _setupCompleteKey = 'setup_complete';
  static const String _deviceIdKey = 'device_id';
  static const String _deviceNameKey = 'device_name';
  static const String _serverInfoKey = 'server_info';

  bool _setupComplete = false;
  String? _deviceId;
  String? _deviceName;
  ServerConnectionInfo? _lastServerInfo;
  bool _isInitialized = false;

  // Getters
  bool get setupComplete => _setupComplete;
  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;
  ServerConnectionInfo? get lastServerInfo => _lastServerInfo;
  bool get isInitialized => _isInitialized;

  /// Initialize the service by loading saved state
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      _setupComplete = prefs.getBool(_setupCompleteKey) ?? false;
      _deviceId = prefs.getString(_deviceIdKey);
      _deviceName = prefs.getString(_deviceNameKey);

      final serverInfoString = prefs.getString(_serverInfoKey);
      if (serverInfoString != null) {
        _lastServerInfo = ServerConnectionInfo.fromString(serverInfoString);
      }

      _isInitialized = true;
      notifyListeners();

      debugPrint('[AppStateService] Initialized - Setup complete: $_setupComplete');
    } catch (e) {
      debugPrint('[AppStateService] Error initializing: $e');
      _isInitialized = true;
    }
  }

  /// Check if setup has been completed
  bool hasCompletedSetup() {
    return _setupComplete;
  }

  /// Get stored server connection info
  ServerConnectionInfo? getStoredServerInfo() {
    return _lastServerInfo;
  }

  /// Get or generate device ID
  Future<String> getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    // Generate new device ID
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 10000;
    _deviceId = 'mobile_${timestamp}_$random';

    await _saveDeviceId(_deviceId!);
    notifyListeners();

    return _deviceId!;
  }

  /// Get or generate device name
  Future<String> getOrCreateDeviceName() async {
    if (_deviceName != null) return _deviceName!;

    // Generate default device name
    _deviceName = 'Mobile Device';

    await _saveDeviceName(_deviceName!);
    notifyListeners();

    return _deviceName!;
  }

  /// Mark setup as complete
  Future<void> markSetupComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_setupCompleteKey, true);

      _setupComplete = true;
      notifyListeners();

      debugPrint('[AppStateService] Setup marked as complete');
    } catch (e) {
      debugPrint('[AppStateService] Error marking setup complete: $e');
    }
  }

  /// Save server connection info
  Future<void> saveServerInfo({
    required String ip,
    required int port,
    String? sessionId,
  }) async {
    try {
      final serverInfo = ServerConnectionInfo(
        ip: ip,
        port: port,
        sessionId: sessionId,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverInfoKey, serverInfo.toString());

      _lastServerInfo = serverInfo;
      notifyListeners();

      debugPrint('[AppStateService] Saved server info: $ip:$port');
    } catch (e) {
      debugPrint('[AppStateService] Error saving server info: $e');
    }
  }

  /// Save device ID
  Future<void> _saveDeviceId(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceIdKey, deviceId);
    } catch (e) {
      debugPrint('[AppStateService] Error saving device ID: $e');
    }
  }

  /// Save device name
  Future<void> _saveDeviceName(String deviceName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceNameKey, deviceName);
    } catch (e) {
      debugPrint('[AppStateService] Error saving device name: $e');
    }
  }

  /// Clear all app state (for debugging/reset)
  Future<void> clearAllState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_setupCompleteKey);
      await prefs.remove(_deviceIdKey);
      await prefs.remove(_deviceNameKey);
      await prefs.remove(_serverInfoKey);

      _setupComplete = false;
      _deviceId = null;
      _deviceName = null;
      _lastServerInfo = null;
      notifyListeners();

      debugPrint('[AppStateService] All state cleared');
    } catch (e) {
      debugPrint('[AppStateService] Error clearing state: $e');
    }
  }
}

/// Simple model for storing server connection information
class ServerConnectionInfo {
  final String ip;
  final int port;
  final String? sessionId;

  ServerConnectionInfo({
    required this.ip,
    required this.port,
    this.sessionId,
  });

  /// Parse from stored string format: "ip:port:sessionId"
  factory ServerConnectionInfo.fromString(String str) {
    final parts = str.split(':');
    if (parts.length < 2) {
      throw FormatException('Invalid server info format: $str');
    }

    return ServerConnectionInfo(
      ip: parts[0],
      port: int.parse(parts[1]),
      sessionId: parts.length > 2 ? parts[2] : null,
    );
  }

  /// Convert to stored string format
  @override
  String toString() {
    if (sessionId != null) {
      return '$ip:$port:$sessionId';
    }
    return '$ip:$port';
  }
}
