import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/api_models.dart';
import '../../models/server_info.dart';
import '../../models/websocket_models.dart';
import 'api_client.dart';
import 'websocket_service.dart';

/// Service for managing server connection and session
class ConnectionService {
  // Singleton pattern
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();

  ApiClient? _apiClient;
  ServerInfo? _serverInfo;
  String? _sessionId;
  Timer? _heartbeatTimer;
  bool _isConnected = false;

  final WebSocketService _webSocketService = WebSocketService();

  /// Check if connected to server
  bool get isConnected => _isConnected;

  /// Get current API client
  ApiClient? get apiClient => _apiClient;

  /// Get current server info
  ServerInfo? get serverInfo => _serverInfo;

  /// Get current session ID
  String? get sessionId => _sessionId;

  /// Get WebSocket message stream
  Stream<WsMessage> get webSocketMessages => _webSocketService.messages;

  // ============================================================================
  // CONNECTION MANAGEMENT
  // ============================================================================

  /// Connect to server using QR code data
  Future<void> connectFromQr(String qrData) async {
    try {
      // Parse QR code JSON
      final serverInfo = ServerInfo.fromJson(
        Map<String, dynamic>.from(
          // ignore: avoid_dynamic_calls
          const JsonDecoder().convert(qrData) as Map,
        ),
      );

      await connectToServer(serverInfo);
    } catch (e) {
      throw Exception('Invalid QR code format: $e');
    }
  }

  /// Connect to server with ServerInfo
  Future<void> connectToServer(ServerInfo serverInfo) async {
    // Create API client
    _apiClient = ApiClient(serverInfo: serverInfo);
    _serverInfo = serverInfo;

    // Test connection with ping
    try {
      await _apiClient!.ping();
    } catch (e) {
      _apiClient = null;
      _serverInfo = null;
      throw Exception('Cannot reach server: $e');
    }

    // Send connect request
    final connectRequest = ConnectRequest(
      deviceId: await _getDeviceId(),
      deviceName: await _getDeviceName(),
      appVersion: '1.0.0',
      platform: Platform.isAndroid ? 'android' : 'ios',
    );

    try {
      final response = await _apiClient!.connect(connectRequest);
      _sessionId = response.sessionId;
      _isConnected = true;

      // Save connection info
      await _saveConnectionInfo(serverInfo, _sessionId!);

      // Start heartbeat
      _startHeartbeat();

      // Connect WebSocket for real-time updates
      await _webSocketService.connect(serverInfo);

      print('Connected to server: ${serverInfo.name}');
      print('Session ID: $_sessionId');
    } catch (e) {
      _apiClient = null;
      _serverInfo = null;
      _sessionId = null;
      throw Exception('Connection failed: $e');
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    if (_apiClient != null && _sessionId != null) {
      try {
        // Send disconnect request
        final request = DisconnectRequest(sessionId: _sessionId!);
        await _apiClient!.disconnect(request);
      } catch (e) {
        print('Error during disconnect: $e');
      }
    }

    // Stop heartbeat
    _stopHeartbeat();

    // Disconnect WebSocket
    _webSocketService.disconnect();

    // Clear state
    _apiClient = null;
    _serverInfo = null;
    _sessionId = null;
    _isConnected = false;

    // Clear saved connection info
    await _clearConnectionInfo();

    print('Disconnected from server');
  }

  /// Try to restore previous connection
  Future<bool> tryRestoreConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final serverJson = prefs.getString('server_info');

    if (serverJson == null) {
      return false;
    }

    try {
      final serverInfo = ServerInfo.fromJson(
        Map<String, dynamic>.from(
          // ignore: avoid_dynamic_calls
          const JsonDecoder().convert(serverJson) as Map,
        ),
      );

      _apiClient = ApiClient(serverInfo: serverInfo);
      _serverInfo = serverInfo;

      // Test if server is reachable
      await _apiClient!.ping();

      // Re-register with server to get fresh session
      final connectRequest = ConnectRequest(
        deviceId: await _getDeviceId(),
        deviceName: await _getDeviceName(),
        appVersion: '1.0.0',
        platform: Platform.isAndroid ? 'android' : 'ios',
      );

      final response = await _apiClient!.connect(connectRequest);
      _sessionId = response.sessionId;
      _isConnected = true;

      // Save new session info
      await _saveConnectionInfo(serverInfo, _sessionId!);

      // Start heartbeat
      _startHeartbeat();

      // Reconnect WebSocket
      await _webSocketService.connect(serverInfo);

      print('Connection restored to: ${serverInfo.name}');
      print('New Session ID: $_sessionId');
      return true;
    } catch (e) {
      print('Failed to restore connection: $e');
      // Don't clear connection info - let user retry!
      // Only clear it when user explicitly chooses "Scan New QR"
      _apiClient = null;
      _isConnected = false;
      return false;
    }
  }

  // ============================================================================
  // HEARTBEAT MECHANISM
  // ============================================================================

  /// Start heartbeat timer
  void _startHeartbeat() {
    _stopHeartbeat();

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendHeartbeat(),
    );
  }

  /// Stop heartbeat timer
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Send heartbeat ping to server
  Future<void> _sendHeartbeat() async {
    if (_apiClient == null) return;

    try {
      await _apiClient!.ping();
      print('Heartbeat sent');
    } catch (e) {
      print('Heartbeat failed: $e');
      // Connection lost - try to reconnect
      await _handleConnectionLoss();
    }
  }

  /// Handle connection loss and attempt reconnection
  Future<void> _handleConnectionLoss() async {
    print('Connection lost - attempting to reconnect...');
    _isConnected = false;
    _stopHeartbeat();

    // Wait before retry
    await Future.delayed(const Duration(seconds: 5));

    // Try to restore connection
    final restored = await tryRestoreConnection();
    if (!restored) {
      print('Reconnection failed');
      await _clearConnectionInfo();
      _apiClient = null;
      _serverInfo = null;
      _sessionId = null;
    }
  }

  // ============================================================================
  // PERSISTENCE
  // ============================================================================

  /// Save connection info to SharedPreferences
  Future<void> _saveConnectionInfo(ServerInfo serverInfo, String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_info', const JsonEncoder().convert(serverInfo.toJson()));
    await prefs.setString('session_id', sessionId);
  }

  /// Clear saved connection info
  Future<void> _clearConnectionInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('server_info');
    await prefs.remove('session_id');
  }

  // ============================================================================
  // DEVICE INFO
  // ============================================================================

  /// Get unique device ID
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');

    if (deviceId == null) {
      // Generate new device ID
      deviceId = 'mobile_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', deviceId);
    }

    return deviceId;
  }

  /// Get device name
  Future<String> _getDeviceName() async {
    // Get device model/name
    // For now, use platform info
    if (Platform.isAndroid) {
      return 'Android Device';
    } else if (Platform.isIOS) {
      return 'iOS Device';
    } else {
      return 'Mobile Device';
    }
  }
}
