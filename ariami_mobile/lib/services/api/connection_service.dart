import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/api_models.dart';
import '../../models/auth_models.dart';
import '../../models/server_info.dart';
import '../../models/websocket_models.dart';
import '../download/download_manager.dart';
import '../library/library_read_facade.dart';
import '../library/library_repository.dart';
import '../offline/offline_playback_service.dart';
import '../sync/library_sync_engine.dart';
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
  int _consecutiveHeartbeatFailures = 0;
  static const int _maxHeartbeatFailures =
      3; // Retry 3 times before going offline

  final WebSocketService _webSocketService = WebSocketService();
  final LibraryRepository _libraryRepository = LibraryRepository();
  late final LibrarySyncEngine _librarySyncEngine = LibrarySyncEngine(
    apiClientProvider: _requireApiClient,
    libraryRepository: _libraryRepository,
  );
  late final LibraryReadFacade _libraryReadFacade = LibraryReadFacade(
    apiClientProvider: () => _apiClient,
    libraryRepository: _libraryRepository,
  );

  // Secure storage for auth tokens
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const String _sessionTokenKey = 'session_token';
  static const String _userIdKey = 'user_id';
  static const String _usernameKey = 'username';
  static const String _deviceIdKey = 'device_id';
  static const Uuid _uuid = Uuid();

  // Auth state
  String? _sessionToken;
  String? _userId;
  String? _username;
  String? _lastRestoreFailureCode;
  String? _lastRestoreFailureMessage;
  Map<String, dynamic>? _lastRestoreFailureDetails;

  // Stream controller to broadcast connection state changes
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  // Stream controller to broadcast session expiry events
  final StreamController<void> _sessionExpiredController =
      StreamController<void>.broadcast();

  /// Check if connected to server
  bool get isConnected => _isConnected;

  /// Get current API client
  ApiClient? get apiClient => _apiClient;

  /// Get current server info
  ServerInfo? get serverInfo => _serverInfo;

  /// Get current session ID
  String? get sessionId => _sessionId;

  /// Get current session token (for authenticated requests)
  String? get sessionToken => _sessionToken;

  /// Get Authorization header map for authenticated requests
  Map<String, String>? get authHeaders {
    final token = _sessionToken;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  /// Get current user ID
  String? get userId => _userId;

  /// Get current username
  String? get username => _username;

  /// Check if user is authenticated
  bool get isAuthenticated => _sessionToken != null;

  /// Get WebSocket message stream
  Stream<WsMessage> get webSocketMessages => _webSocketService.messages;

  /// Unified library read facade for deterministic v1/v2 source selection.
  LibraryReadFacade get libraryReadFacade => _libraryReadFacade;

  /// Stream of connection state changes (true = connected, false = disconnected)
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  /// Stream that emits when session expires (401 from server)
  Stream<void> get sessionExpiredStream => _sessionExpiredController.stream;

  /// Most recent reconnect failure code from [tryRestoreConnection], if any.
  String? get lastRestoreFailureCode => _lastRestoreFailureCode;

  /// Most recent reconnect failure message from [tryRestoreConnection], if any.
  String? get lastRestoreFailureMessage => _lastRestoreFailureMessage;

  /// Most recent reconnect failure details from [tryRestoreConnection], if any.
  Map<String, dynamic>? get lastRestoreFailureDetails =>
      _lastRestoreFailureDetails;

  bool get didLastRestoreFailForAuth =>
      _lastRestoreFailureCode == ApiErrorCodes.authRequired ||
      _lastRestoreFailureCode == ApiErrorCodes.sessionExpired;

  /// Check if we have saved server info (even if not currently connected)
  bool get hasServerInfo => _serverInfo != null;

  /// Resolve the current device display name used for server connections.
  Future<String> getCurrentDeviceName() => _getDeviceName();

  // ============================================================================
  // AUTHENTICATION
  // ============================================================================

  /// Register a new user account and connect to server
  Future<void> register({
    required String username,
    required String password,
    required ServerInfo serverInfo,
  }) async {
    final deviceId = await _getDeviceId();
    final deviceName = await _getDeviceName();

    // Create API client
    _apiClient = ApiClient(
      serverInfo: serverInfo,
      deviceId: deviceId,
      deviceName: deviceName,
      onSessionExpired: handleSessionExpired,
    );
    _serverInfo = serverInfo;
    _applyDownloadLimits(serverInfo);

    // Test connection with ping
    try {
      await _apiClient!.ping();
    } catch (e) {
      _apiClient = null;
      _serverInfo = null;
      throw Exception('Cannot reach server: $e');
    }

    // Register user
    final registerRequest = RegisterRequest(
      username: username,
      password: password,
    );

    try {
      await _apiClient!.register(registerRequest);

      // Login immediately to create a valid session for protected endpoints
      final loginResponse = await _apiClient!.login(
        LoginRequest(
          username: username,
          password: password,
          deviceId: deviceId,
          deviceName: deviceName,
        ),
      );

      // Store auth info securely
      _sessionToken = loginResponse.sessionToken;
      _userId = loginResponse.userId;
      _username = loginResponse.username;
      await _saveAuthInfo();

      // Set session token on API client for authenticated requests
      _apiClient!.sessionToken = _sessionToken;

      // Now complete the connection with a valid session
      await _completeAuthConnection(serverInfo, deviceId, deviceName);

      print('Registered and connected as: $_username');
    } catch (e) {
      _apiClient = null;
      _serverInfo = null;
      _sessionToken = null;
      _userId = null;
      _username = null;
      rethrow;
    }
  }

  /// Login with username and password
  Future<void> login({
    required String username,
    required String password,
    required ServerInfo serverInfo,
  }) async {
    final deviceId = await _getDeviceId();
    final deviceName = await _getDeviceName();

    // Create API client
    _apiClient = ApiClient(
      serverInfo: serverInfo,
      deviceId: deviceId,
      deviceName: deviceName,
      onSessionExpired: handleSessionExpired,
    );
    _serverInfo = serverInfo;
    _applyDownloadLimits(serverInfo);

    // Test connection with ping
    try {
      await _apiClient!.ping();
    } catch (e) {
      _apiClient = null;
      _serverInfo = null;
      throw Exception('Cannot reach server: $e');
    }

    // Login
    final loginRequest = LoginRequest(
      username: username,
      password: password,
      deviceId: deviceId,
      deviceName: deviceName,
    );

    try {
      final response = await _apiClient!.login(loginRequest);

      // Store auth info securely
      _sessionToken = response.sessionToken;
      _userId = response.userId;
      _username = response.username;
      await _saveAuthInfo();

      // Set session token on API client for authenticated requests
      _apiClient!.sessionToken = _sessionToken;

      // Complete connection setup
      await _completeAuthConnection(serverInfo, deviceId, deviceName);

      print('Logged in and connected as: $_username');
    } catch (e) {
      _apiClient = null;
      _serverInfo = null;
      _sessionToken = null;
      _userId = null;
      _username = null;
      rethrow;
    }
  }

  /// Logout and clear auth state
  Future<void> logout() async {
    if (_apiClient != null && _sessionToken != null) {
      try {
        await _apiClient!.logout(_sessionToken!);
      } catch (e) {
        print('Error during logout: $e');
      }
    }

    // Clear auth state
    _sessionToken = null;
    _userId = null;
    _username = null;
    await _clearAuthInfo();

    // Clear session token from API client
    if (_apiClient != null) {
      _apiClient!.sessionToken = null;
    }

    // Disconnect
    await disconnect(isManual: true);
  }

  /// Handle session expiry (called when server returns 401 SESSION_EXPIRED or AUTH_REQUIRED)
  /// Clears auth state and emits event for UI to navigate to login
  Future<void> handleSessionExpired() async {
    print('Session expired - clearing auth state');

    // Clear auth state (don't call server logout - session is already invalid)
    _sessionToken = null;
    _userId = null;
    _username = null;
    await _clearAuthInfo();

    // Clear session token from API client
    if (_apiClient != null) {
      _apiClient!.sessionToken = null;
    }

    // Disconnect without calling server (session is invalid anyway)
    _stopLibrarySyncEngine();
    _stopHeartbeat();
    _webSocketService.disconnect();
    _apiClient = null;
    _sessionId = null;
    _isConnected = false;
    _connectionStateController.add(false);

    // Emit session expired event for UI to handle navigation
    _sessionExpiredController.add(null);
  }

  /// Complete the connection after auth (shared by login and register)
  Future<void> _completeAuthConnection(
    ServerInfo serverInfo,
    String deviceId,
    String deviceName,
  ) async {
    // Send legacy connect request for session tracking
    final connectRequest = ConnectRequest(
      deviceId: deviceId,
      deviceName: deviceName,
      appVersion: '1.0.0',
      platform: Platform.isAndroid ? 'android' : 'ios',
    );

    final response = await _apiClient!.connect(connectRequest);
    await _applyDeviceIdFromServer(
      responseDeviceId: response.deviceId,
      currentDeviceId: deviceId,
      deviceName: deviceName,
      serverInfo: serverInfo,
    );
    _sessionId = response.sessionId;
    _isConnected = true;
    _isManuallyDisconnected = false;
    _consecutiveHeartbeatFailures = 0;
    _connectionStateController.add(true);

    // Notify offline service that connection is restored
    await OfflinePlaybackService().notifyConnectionRestored();

    // Save connection info
    await _saveConnectionInfo(serverInfo, _sessionId!);

    // Start heartbeat
    _startHeartbeat();

    // Connect WebSocket for real-time updates
    _webSocketService.onReconnected = _handleWebSocketReconnect;
    _webSocketService.onDisconnected = _handleWebSocketDisconnect;
    _webSocketService.onMessage = _handleWebSocketMessage;
    await _webSocketService.connect(serverInfo);
    await _sendWebSocketIdentify();
    _startLibrarySyncEngine();
  }

  /// Load stored auth info on app start
  Future<void> loadAuthInfo() async {
    _sessionToken = await _secureStorage.read(key: _sessionTokenKey);
    _userId = await _secureStorage.read(key: _userIdKey);
    _username = await _secureStorage.read(key: _usernameKey);

    if (_sessionToken != null) {
      print('Loaded auth info for user: $_username');
    }
  }

  /// Save auth info to secure storage
  Future<void> _saveAuthInfo() async {
    if (_sessionToken != null) {
      await _secureStorage.write(key: _sessionTokenKey, value: _sessionToken);
    }
    if (_userId != null) {
      await _secureStorage.write(key: _userIdKey, value: _userId);
    }
    if (_username != null) {
      await _secureStorage.write(key: _usernameKey, value: _username);
    }
  }

  /// Clear auth info from secure storage
  Future<void> _clearAuthInfo() async {
    await _secureStorage.delete(key: _sessionTokenKey);
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _usernameKey);
  }

  void _applyDownloadLimits(ServerInfo serverInfo) {
    final limits = serverInfo.downloadLimits;
    DownloadManager().setMaxConcurrentDownloads(limits.maxConcurrentPerUser);
  }

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
    final deviceId = await _getDeviceId();
    final deviceName = await _getDeviceName();

    // Create API client (include session token if authenticated)
    _apiClient = ApiClient(
      serverInfo: serverInfo,
      deviceId: deviceId,
      deviceName: deviceName,
      sessionToken: _sessionToken,
      onSessionExpired: handleSessionExpired,
    );
    _serverInfo = serverInfo;
    _applyDownloadLimits(serverInfo);

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
      deviceId: deviceId,
      deviceName: deviceName,
      appVersion: '1.0.0',
      platform: Platform.isAndroid ? 'android' : 'ios',
    );

    try {
      final response = await _apiClient!.connect(connectRequest);
      await _applyDeviceIdFromServer(
        responseDeviceId: response.deviceId,
        currentDeviceId: deviceId,
        deviceName: deviceName,
        serverInfo: serverInfo,
      );
      _sessionId = response.sessionId;
      _isConnected = true;
      _isManuallyDisconnected = false;
      _consecutiveHeartbeatFailures = 0; // Reset failure counter
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
      _webSocketService.onMessage = _handleWebSocketMessage;
      await _webSocketService.connect(serverInfo);
      await _sendWebSocketIdentify();
      _startLibrarySyncEngine();

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

    if (_apiClient != null && _isConnected) {
      try {
        // In auth mode, server resolves the device from bearer session.
        // In legacy mode, include deviceId explicitly.
        final request = DisconnectRequest(deviceId: _apiClient!.deviceId);
        await _apiClient!.disconnect(request);
      } catch (e) {
        print('Error during disconnect: $e');
      }
    }

    // Stop heartbeat
    _stopLibrarySyncEngine();
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
    _clearLastRestoreFailure();

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
      _applyDownloadLimits(serverInfo);

      // Quick reachability check first (fails fast if server is down)
      if (!await _isServerReachable(serverInfo)) {
        print('Server not reachable - skipping connection attempt');
        _serverInfo = serverInfo; // Keep server info for later reconnect
        return false;
      }

      // Server is reachable - try full connection with reduced timeout
      final deviceId = await _getDeviceId();
      final deviceName = await _getDeviceName();
      _apiClient = ApiClient(
        serverInfo: serverInfo,
        timeout: const Duration(seconds: 3),
        deviceId: deviceId,
        deviceName: deviceName,
        sessionToken: _sessionToken, // Include session token if authenticated
        onSessionExpired: handleSessionExpired,
      );
      _serverInfo = serverInfo;
      _applyDownloadLimits(serverInfo);

      // Test if server API is responding
      await _apiClient!.ping();

      // Re-register with server to get fresh session
      final connectRequest = ConnectRequest(
        deviceId: deviceId,
        deviceName: deviceName,
        appVersion: '1.0.0',
        platform: Platform.isAndroid ? 'android' : 'ios',
      );

      final response = await _apiClient!.connect(connectRequest);
      await _applyDeviceIdFromServer(
        responseDeviceId: response.deviceId,
        currentDeviceId: deviceId,
        deviceName: deviceName,
        serverInfo: serverInfo,
        timeout: const Duration(seconds: 3),
      );
      _sessionId = response.sessionId;
      _isConnected = true;
      _isManuallyDisconnected = false;
      _consecutiveHeartbeatFailures = 0; // Reset failure counter
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
      _webSocketService.onMessage = _handleWebSocketMessage;
      await _webSocketService.connect(serverInfo);
      await _sendWebSocketIdentify();
      _startLibrarySyncEngine();

      print('Connection restored to: ${serverInfo.name}');
      print('New Session ID: $_sessionId');
      return true;
    } on ApiException catch (e) {
      _setLastRestoreFailure(
        code: e.code,
        message: e.message,
        details: e.details,
      );

      if (_isAuthReconnectFailure(e.code)) {
        print('Reconnect requires authentication (${e.code})');
        // ApiClient already invokes onSessionExpired for 401 auth errors when a
        // session token exists. Force handling only for missing-token auth flow.
        if (_sessionToken == null) {
          await handleSessionExpired();
        }
      } else {
        print('Failed to restore connection: $e');
      }

      // Keep _serverInfo so we know where to reconnect/login
      _apiClient = null;
      _isConnected = false;
      // Note: Don't broadcast here - _handleConnectionLoss will do it
      return false;
    } catch (e) {
      _setLastRestoreFailure(
        code: ApiErrorCodes.serverError,
        message: e.toString(),
      );
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

  bool _isAuthReconnectFailure(String code) =>
      code == ApiErrorCodes.authRequired ||
      code == ApiErrorCodes.sessionExpired;

  void _clearLastRestoreFailure() {
    _lastRestoreFailureCode = null;
    _lastRestoreFailureMessage = null;
    _lastRestoreFailureDetails = null;
  }

  void _setLastRestoreFailure({
    required String code,
    required String message,
    Map<String, dynamic>? details,
  }) {
    _lastRestoreFailureCode = code;
    _lastRestoreFailureMessage = message;
    _lastRestoreFailureDetails = details;
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
        _applyDownloadLimits(_serverInfo!);
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

    // Ensure this socket is identified on the server
    await _sendWebSocketIdentify();

    // If we're already connected, no need to do anything
    if (_isConnected && _apiClient != null) {
      print('Already connected, skipping restore');
      unawaited(_librarySyncEngine.syncNow());
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
      _stopLibrarySyncEngine();
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

  void _handleWebSocketMessage(WsMessage message) {
    if (message.type != WsMessageType.syncTokenAdvanced) {
      return;
    }

    final latestToken = _parseLatestToken(message.data?['latestToken']);
    if (latestToken <= 0) {
      return;
    }

    unawaited(_librarySyncEngine.syncUntil(latestToken));
  }

  int _parseLatestToken(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  Future<void> _sendWebSocketIdentify() async {
    if (!_webSocketService.isConnected) return;
    final deviceId = await _getDeviceId();
    final deviceName = await _getDeviceName();
    _webSocketService.sendMessage(
      IdentifyMessage(
        deviceId: deviceId,
        deviceName: deviceName,
        sessionToken: _sessionToken,
      ),
    );
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
      if (_webSocketService.isConnected) {
        print('Auto offline mode - attempting to restore connection...');
        final restored = await tryRestoreConnection();
        if (restored) {
          print('✅ Connection restored via auto-reconnect!');
        } else {
          print('Reconnection attempt failed, will retry in 30s');
        }
      } else {
        print('Auto offline mode - waiting for WebSocket before restore');
      }
      return;
    }

    // Normal connected mode - send ping
    if (_apiClient == null) return;

    try {
      final deviceId = await _getDeviceId();
      await _apiClient!.ping(deviceId: deviceId);
      // Reset failure counter on success
      if (_consecutiveHeartbeatFailures > 0) {
        print(
            'Heartbeat recovered after $_consecutiveHeartbeatFailures failures');
      }
      _consecutiveHeartbeatFailures = 0;
      print('Heartbeat sent');
    } catch (e) {
      _consecutiveHeartbeatFailures++;
      print(
          'Heartbeat failed ($_consecutiveHeartbeatFailures/$_maxHeartbeatFailures): $e');

      // Only go offline after multiple consecutive failures
      if (_consecutiveHeartbeatFailures >= _maxHeartbeatFailures) {
        print('Max heartbeat failures reached - going offline');
        _consecutiveHeartbeatFailures = 0; // Reset for next time
        await _handleConnectionLoss();
      } else {
        print(
            'Will retry heartbeat (${_maxHeartbeatFailures - _consecutiveHeartbeatFailures} attempts remaining)');
      }
    }
  }

  /// Handle connection loss - auto-enable offline mode
  Future<void> _handleConnectionLoss() async {
    print('Connection lost - enabling auto offline mode');
    _stopLibrarySyncEngine();
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

  Future<void> _saveDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, deviceId);
  }

  Future<void> _applyDeviceIdFromServer({
    required String? responseDeviceId,
    required String currentDeviceId,
    required String deviceName,
    required ServerInfo serverInfo,
    Duration? timeout,
  }) async {
    if (responseDeviceId == null || responseDeviceId.isEmpty) return;
    if (responseDeviceId == currentDeviceId) return;

    await _saveDeviceId(responseDeviceId);

    if (_apiClient != null) {
      _apiClient = ApiClient(
        serverInfo: serverInfo,
        timeout: timeout ?? _apiClient!.timeout,
        deviceId: responseDeviceId,
        deviceName: deviceName,
        sessionToken: _sessionToken,
        onSessionExpired: handleSessionExpired,
      );
    }
  }

  ApiClient _requireApiClient() {
    final client = _apiClient;
    if (client == null) {
      throw StateError('API client unavailable for sync operation');
    }
    return client;
  }

  void _startLibrarySyncEngine() {
    _librarySyncEngine.start();
  }

  void _stopLibrarySyncEngine() {
    _librarySyncEngine.stop();
  }

  // ============================================================================
  // DEVICE INFO
  // ============================================================================

  /// Get unique device ID
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null || deviceId.isEmpty || deviceId == 'unknown-device') {
      deviceId = _uuid.v4();
      await prefs.setString(_deviceIdKey, deviceId);
      print('Generated new deviceId: $deviceId');
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
