import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/server_info.dart';
import '../../models/connection_response.dart';
import '../../models/websocket_messages.dart';
import 'api_client.dart';
import 'websocket_service.dart';

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

class ConnectionService extends ChangeNotifier {
  ServerInfo? _serverInfo;
  ApiClient? _apiClient;
  WebSocketService? _webSocketService;
  ConnectionState _state = ConnectionState.disconnected;
  String? _errorMessage;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  // Stream subscriptions for WebSocket events
  StreamSubscription<LibraryUpdateMessage>? _libraryUpdatesSubscription;
  StreamSubscription<NowPlayingMessage>? _nowPlayingSubscription;
  StreamSubscription<ServerNotificationMessage>? _notificationsSubscription;

  // Getters
  ServerInfo? get serverInfo => _serverInfo;
  ApiClient? get apiClient => _apiClient;
  WebSocketService? get webSocketService => _webSocketService;
  ConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _state == ConnectionState.connected;

  ConnectionService() {
    _loadSavedConnection();
  }

  // Load saved connection from shared preferences
  Future<void> _loadSavedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverInfoJson = prefs.getString('server_info');

      if (serverInfoJson != null) {
        // We have a saved connection, but don't auto-connect
        // Just make it available for manual reconnection
        print('Found saved server info');
      }
    } catch (e) {
      print('Error loading saved connection: $e');
    }
  }

  // Save connection to shared preferences
  Future<void> _saveConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_serverInfo != null) {
        await prefs.setString('server_info',
            '${_serverInfo!.ip}:${_serverInfo!.port}:${_serverInfo!.sessionId}');
      }
    } catch (e) {
      print('Error saving connection: $e');
    }
  }

  // Clear saved connection
  Future<void> _clearSavedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('server_info');
    } catch (e) {
      print('Error clearing saved connection: $e');
    }
  }

  // Connect to server
  Future<bool> connect({
    required String ip,
    required int port,
    required String deviceId,
    required String deviceName,
  }) async {
    print('Attempting to connect to $ip:$port');
    _setState(ConnectionState.connecting);
    _reconnectAttempts = 0;

    try {
      // Create server info and API client
      _serverInfo = ServerInfo(ip: ip, port: port);
      _apiClient = ApiClient(serverInfo: _serverInfo!);

      // Test connection with ping
      final pingSuccess = await _apiClient!.ping();
      if (!pingSuccess) {
        _setError('Server not responding');
        return false;
      }

      // Connect and get session
      final response = await _apiClient!.connect(
        deviceId: deviceId,
        deviceName: deviceName,
        appVersion: '1.0.0',
        platform: Platform.operatingSystem,
      );

      if (response == null) {
        _setError('Failed to establish connection');
        return false;
      }

      // Update server info with session ID
      _serverInfo = _serverInfo!.copyWith(sessionId: response.sessionId);
      _apiClient = ApiClient(serverInfo: _serverInfo!);

      // Save connection
      await _saveConnection();

      // Initialize WebSocket service
      _webSocketService = WebSocketService();
      _setupWebSocketListeners();

      // Connect WebSocket
      await _connectWebSocket();

      // Start heartbeat
      _startHeartbeat();

      _setState(ConnectionState.connected);
      print('Connected successfully. Session: ${response.sessionId}');
      return true;
    } catch (e) {
      _setError('Connection error: $e');
      return false;
    }
  }

  /// Attempt to automatically reconnect using stored server info
  /// Used during app startup to restore previous connection
  Future<bool> attemptAutoReconnect({
    required String ip,
    required int port,
    required String deviceId,
    required String deviceName,
  }) async {
    debugPrint('[ConnectionService] Attempting auto-reconnect to $ip:$port');

    try {
      // Use the same connect logic
      return await connect(
        ip: ip,
        port: port,
        deviceId: deviceId,
        deviceName: deviceName,
      );
    } catch (e) {
      debugPrint('[ConnectionService] Auto-reconnect failed: $e');
      return false;
    }
  }

  // Disconnect from server
  Future<void> disconnect() async {
    print('Disconnecting from server');

    // Stop timers
    _stopHeartbeat();
    _stopReconnect();

    // Disconnect WebSocket
    await _disconnectWebSocket();

    // Disconnect from server
    if (_serverInfo?.sessionId != null && _apiClient != null) {
      try {
        await _apiClient!.disconnect(_serverInfo!.sessionId!);
      } catch (e) {
        print('Error during disconnect: $e');
      }
    }

    // Clear state
    await _clearSavedConnection();
    _serverInfo = null;
    _apiClient = null;
    _webSocketService = null;
    _setState(ConnectionState.disconnected);
  }

  // Start heartbeat timer
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      await _sendHeartbeat();
    });
    print('Heartbeat started');
  }

  // Stop heartbeat timer
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // Send heartbeat ping
  Future<void> _sendHeartbeat() async {
    if (_apiClient == null || _state != ConnectionState.connected) {
      return;
    }

    try {
      final success = await _apiClient!.ping();
      if (!success) {
        print('Heartbeat failed, attempting reconnect');
        _handleConnectionLost();
      }
    } catch (e) {
      print('Heartbeat error: $e');
      _handleConnectionLost();
    }
  }

  // Handle connection lost
  void _handleConnectionLost() {
    if (_state == ConnectionState.reconnecting) {
      return; // Already reconnecting
    }

    _stopHeartbeat();
    _setState(ConnectionState.reconnecting);
    _reconnectAttempts = 0;
    _attemptReconnect();
  }

  // Attempt to reconnect with exponential backoff
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setError('Connection lost. Maximum reconnect attempts reached.');
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2); // Exponential backoff

    print('Reconnect attempt $_reconnectAttempts of $_maxReconnectAttempts in ${delay.inSeconds}s');

    _reconnectTimer = Timer(delay, () async {
      if (_apiClient == null) return;

      try {
        final success = await _apiClient!.ping();
        if (success) {
          print('Reconnected successfully');
          _reconnectAttempts = 0;
          _setState(ConnectionState.connected);
          _startHeartbeat();
        } else {
          _attemptReconnect();
        }
      } catch (e) {
        print('Reconnect error: $e');
        _attemptReconnect();
      }
    });
  }

  // Stop reconnect timer
  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // Set connection state
  void _setState(ConnectionState newState) {
    _state = newState;
    if (newState == ConnectionState.connected) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  // Set error state
  void _setError(String message) {
    _errorMessage = message;
    _state = ConnectionState.error;
    notifyListeners();
  }

  // ===== WEBSOCKET METHODS =====

  /// Connect to WebSocket server
  Future<void> _connectWebSocket() async {
    if (_serverInfo == null || _serverInfo!.sessionId == null) {
      debugPrint('[ConnectionService] Cannot connect WebSocket: no session');
      return;
    }

    if (_webSocketService == null) {
      debugPrint('[ConnectionService] Cannot connect WebSocket: service not initialized');
      return;
    }

    try {
      final success = await _webSocketService!.connect(
        wsUrl: _serverInfo!.wsUrl,
        sessionId: _serverInfo!.sessionId!,
      );

      if (success) {
        debugPrint('[ConnectionService] WebSocket connected');
      } else {
        debugPrint('[ConnectionService] WebSocket connection failed');
      }
    } catch (e) {
      debugPrint('[ConnectionService] WebSocket connection error: $e');
    }
  }

  /// Disconnect from WebSocket server
  Future<void> _disconnectWebSocket() async {
    // Cancel subscriptions
    await _libraryUpdatesSubscription?.cancel();
    await _nowPlayingSubscription?.cancel();
    await _notificationsSubscription?.cancel();

    _libraryUpdatesSubscription = null;
    _nowPlayingSubscription = null;
    _notificationsSubscription = null;

    // Disconnect service
    await _webSocketService?.disconnect();
  }

  /// Set up WebSocket event listeners
  void _setupWebSocketListeners() {
    if (_webSocketService == null) return;

    // Listen for library updates
    _libraryUpdatesSubscription = _webSocketService!.libraryUpdates.listen(
      (message) {
        debugPrint('[ConnectionService] Library update: ${message.updateType}');
        // Notify listeners that library was updated
        // In Phase 5, this will trigger library refresh
        notifyListeners();
      },
    );

    // Listen for now playing updates from other clients
    _nowPlayingSubscription = _webSocketService!.nowPlaying.listen(
      (message) {
        debugPrint('[ConnectionService] Now playing update from ${message.deviceId}');
        // Future: Update UI to show what other clients are playing
      },
    );

    // Listen for server notifications
    _notificationsSubscription = _webSocketService!.notifications.listen(
      (message) {
        debugPrint('[ConnectionService] Server notification [${message.severity}]: ${message.message}');
        // Future: Show notifications to user
      },
    );
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _stopReconnect();
    _disconnectWebSocket();
    super.dispose();
  }
}
