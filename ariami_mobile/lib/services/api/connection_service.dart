import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/api_models.dart';
import '../../models/server_info.dart';
import '../../models/websocket_models.dart';
import '../offline/offline_playback_service.dart';
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
  bool _isManuallyDisconnected = false;

  final WebSocketService _webSocketService = WebSocketService();

  // Stream controller to broadcast connection state changes
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

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

  /// Stream of connection state changes (true = connected, false = disconnected)
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  /// Check if we have saved server info (even if not currently connected)
  bool get hasServerInfo => _serverInfo != null;

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
      _connectionStateController.add(true); // Broadcast connected state

      // Notify offline service that connection is restored
      await OfflinePlaybackService().notifyConnectionRestored();

      // Save connection info
      await _saveConnectionInfo(serverInfo, _sessionId!);

      // Start heartbeat
      _startHeartbeat();

      // Connect WebSocket for real-time updates
      _webSocketService.onReconnected = _handleWebSocketReconnect;
      _webSocketService.onDisconnected = _handleWebSocketDisconnect;
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
  /// @param isManual - true if user initiated disconnect (manual offline)
  Future<void> disconnect({bool isManual = false}) async {
    _isManuallyDisconnected = isManual;

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
    _sessionId = null;
    _isConnected = false;
    _connectionStateController.add(false); // Broadcast disconnected state

    // Keep serverInfo in memory for potential reconnection
    // Don't clear saved connection info - user may want to reconnect later
    // Only clear it when user explicitly chooses "Scan New QR"
    print(
      isManual
          ? 'Disconnected from server (manual)'
          : 'Disconnected from server (auto)',
    );
  }

  /// Try to restore previous connection
  Future<bool> tryRestoreConnection() async {
    // Don't attempt reconnect if in manual offline mode
    if (OfflinePlaybackService().isManualOfflineModeEnabled) {
      print('Manual offline mode enabled - skipping reconnect attempt');
      return false;
    }

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

      // Quick reachability check first (fails fast if server is down)
      if (!await _isServerReachable(serverInfo)) {
        print('Server not reachable - skipping connection attempt');
        _serverInfo = serverInfo; // Keep server info for later reconnect
        return false;
      }

      // Server is reachable - try full connection with reduced timeout
      _apiClient = ApiClient(
        serverInfo: serverInfo,
        timeout: const Duration(seconds: 3),
      );
      _serverInfo = serverInfo;

      // Test if server API is responding
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
      _connectionStateController.add(true); // Broadcast connected state

      // Notify offline service that connection is restored
      await OfflinePlaybackService().notifyConnectionRestored();

      // Save new session info
      await _saveConnectionInfo(serverInfo, _sessionId!);

      // Start heartbeat
      _startHeartbeat();

      // Reconnect WebSocket
      _webSocketService.onReconnected = _handleWebSocketReconnect;
      _webSocketService.onDisconnected = _handleWebSocketDisconnect;
      await _webSocketService.connect(serverInfo);

      print('Connection restored to: ${serverInfo.name}');
      print('New Session ID: $_sessionId');
      return true;
    } catch (e) {
      print('Failed to restore connection: $e');
      // Don't clear connection info - let user retry!
      // Only clear it when user explicitly chooses "Scan New QR"
      // Keep _serverInfo so we know where to reconnect
      _apiClient = null;
      _isConnected = false;
      // Note: Don't broadcast here - _handleConnectionLoss will do it
      return false;
    }
  }

  /// Load server info from storage without attempting connection
  /// Used to check if we have saved server info
  Future<void> loadServerInfoFromStorage() async {
    if (_serverInfo != null) return; // Already loaded

    final prefs = await SharedPreferences.getInstance();
    final serverJson = prefs.getString('server_info');

    if (serverJson != null) {
      try {
        _serverInfo = ServerInfo.fromJson(
          Map<String, dynamic>.from(
            const JsonDecoder().convert(serverJson) as Map,
          ),
        );
        print('Loaded server info from storage: ${_serverInfo?.name}');
      } catch (e) {
        print('Failed to parse stored server info: $e');
      }
    }
  }

  // ============================================================================
  // REACHABILITY CHECK
  // ============================================================================

  /// Quick check if server is reachable at TCP level
  /// Returns true if we can establish a socket connection
  /// Used for fast-fail detection when server is completely unreachable
  Future<bool> _isServerReachable(
    ServerInfo serverInfo, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    try {
      final socket = await Socket.connect(
        serverInfo.server,
        serverInfo.port,
        timeout: timeout,
      );
      await socket.close();
      return true;
    } catch (e) {
      print('Server not reachable: $e');
      return false;
    }
  }

  // ============================================================================
  // WEBSOCKET RECONNECT HANDLER
  // ============================================================================

  /// Called when WebSocket reconnects after being disconnected
  /// This attempts to restore the full REST API connection
  void _handleWebSocketReconnect() async {
    print('WebSocket reconnected - attempting full connection restore...');

    // If we're already connected, no need to do anything
    if (_isConnected && _apiClient != null) {
      print('Already connected, skipping restore');
      return;
    }

    // Try to restore the full connection (REST API + session)
    final restored = await tryRestoreConnection();

    if (restored) {
      print('Full connection restored via WebSocket reconnect');
      // connectionStateStream will be notified by tryRestoreConnection
    } else {
      print('Failed to restore full connection after WebSocket reconnect');
    }
  }

  /// Called when WebSocket disconnects
  /// This automatically enables offline mode so user can continue using the app
  void _handleWebSocketDisconnect() async {
    print('WebSocket disconnect detected');

    // Only handle if we thought we were connected
    if (_isConnected) {
      _isConnected = false;
      _apiClient = null;
      _sessionId = null;

      // Notify offline service (auto offline)
      await OfflinePlaybackService().notifyConnectionLost();

      // Broadcast disconnected state
      _connectionStateController.add(false);

      // Keep heartbeat running during auto offline for reconnection attempts
      // Only stop heartbeat if manual offline mode
      if (OfflinePlaybackService().isManualOfflineModeEnabled) {
        print('Manual offline - stopping heartbeat');
        _stopHeartbeat();
      } else {
        print('Auto offline - keeping heartbeat active for auto-reconnect');
      }
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
    // Don't send heartbeat if manually disconnected
    if (_isManuallyDisconnected) return;

    // Don't send heartbeat if manual offline mode is enabled
    if (OfflinePlaybackService().isManualOfflineModeEnabled) {
      print('Heartbeat skipped - manual offline mode enabled');
      return;
    }

    // Check if we're in auto offline mode (disconnected but should auto-reconnect)
    if (!_isConnected &&
        OfflinePlaybackService().offlineMode == OfflineMode.autoOffline) {
      print('Auto offline mode - attempting to restore connection...');
      final restored = await tryRestoreConnection();
      if (restored) {
        print('✅ Connection restored via auto-reconnect!');
      } else {
        print('Reconnection attempt failed, will retry in 30s');
      }
      return;
    }

    // Normal connected mode - send ping
    if (_apiClient == null) return;

    try {
      await _apiClient!.ping();
      print('Heartbeat sent');
    } catch (e) {
      print('Heartbeat failed: $e');
      // Connection lost - handle auto offline
      await _handleConnectionLoss();
    }
  }

  /// Handle connection loss - auto-enable offline mode
  Future<void> _handleConnectionLoss() async {
    print('Connection lost - enabling auto offline mode');
    _isConnected = false;
    _apiClient = null;
    _sessionId = null;

    // Notify OfflinePlaybackService (won't transition if manual offline)
    await OfflinePlaybackService().notifyConnectionLost();

    // Broadcast disconnected state
    _connectionStateController.add(false);

    // Keep heartbeat running during auto offline for reconnection attempts
    // Heartbeat will call tryRestoreConnection() periodically
    // Only stop heartbeat if manual offline mode
    if (OfflinePlaybackService().isManualOfflineModeEnabled) {
      print('Manual offline - stopping heartbeat');
      _stopHeartbeat();
    } else {
      print('Auto offline - keeping heartbeat active for auto-reconnect');
    }
  }

  // ============================================================================
  // PERSISTENCE
  // ============================================================================

  /// Save connection info to SharedPreferences
  Future<void> _saveConnectionInfo(
    ServerInfo serverInfo,
    String sessionId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'server_info',
      const JsonEncoder().convert(serverInfo.toJson()),
    );
    await prefs.setString('session_id', sessionId);
  }

  // ============================================================================
  // DEVICE INFO
  // ============================================================================

  /// Get unique device ID
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');

    return deviceId ?? 'unknown-device';
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
