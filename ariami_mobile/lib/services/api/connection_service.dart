import 'dart:async';
import 'dart:io';
import '../../models/api_models.dart';
import '../../models/auth_models.dart';
import '../../models/server_info.dart';
import '../../models/websocket_models.dart';
import '../download/download_manager.dart';
import '../audio/playback_state_manager.dart';
import '../library/library_read_facade.dart';
import '../library/library_pin_storage.dart';
import '../library/library_repository.dart';
import '../offline/offline_playback_service.dart';
import '../sync/library_sync_engine.dart';
import 'api_client.dart';
import 'websocket_service.dart';
import 'connection/connection_state_manager.dart';
import 'connection/auth_manager.dart';
import 'connection/server_info_manager.dart';
import 'connection/connection_lifecycle_manager.dart';
import 'connection/heartbeat_manager.dart';
import 'connection/websocket_handler.dart';
import 'connection/device_info_manager.dart';
import 'connection/connection_persistence_manager.dart';
import 'connection/endpoint_switch_handler.dart';

/// Service for managing server connection and session.
///
/// This is a facade that coordinates multiple specialized modules:
/// - [ConnectionStateManager]: Core state and streams
/// - [AuthManager]: Authentication state and secure storage
/// - [ServerInfoManager]: Server metadata and endpoint resolution
/// - [ConnectionLifecycleManager]: Connect/disconnect/restore logic
/// - [HeartbeatManager]: Health checks and auto-reconnect
/// - [WebSocketHandler]: WebSocket events and message handling
/// - [DeviceInfoManager]: Device ID and name
/// - [ConnectionPersistenceManager]: SharedPreferences and secure storage
/// - [EndpointSwitchHandler]: LAN/Tailscale failover
///
/// All public methods and getters maintain 100% backward compatibility
/// with the original monolithic implementation.
class ConnectionService {
  // Singleton pattern
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;

  // ============================================================================
  // MODULES
  // ============================================================================

  late final ConnectionStateManager _stateManager;
  late final AuthManager _authManager;
  late final ServerInfoManager _serverInfoManager;
  late final ConnectionLifecycleManager _lifecycleManager;
  late final HeartbeatManager _heartbeatManager;
  late final WebSocketHandler _webSocketHandler;
  late final DeviceInfoManager _deviceInfoManager;
  late final ConnectionPersistenceManager _persistenceManager;
  late final EndpointSwitchHandler _endpointSwitchHandler;
  Future<bool>? _restoreConnectionInFlight;

  // Legacy services still managed directly
  final WebSocketService _webSocketService = WebSocketService();
  final LibraryRepository _libraryRepository = LibraryRepository();
  final StreamController<WsMessage> _messageController =
      StreamController<WsMessage>.broadcast();
  late final LibrarySyncEngine _librarySyncEngine;
  late final LibraryReadFacade _libraryReadFacade;

  // ============================================================================
  // CONSTRUCTOR
  // ============================================================================

  ConnectionService._internal() {
    // Initialize persistence first (needed by other modules)
    _persistenceManager = ConnectionPersistenceManager();

    // Initialize state managers
    _stateManager = ConnectionStateManager();
    _authManager = AuthManager(
      persistence: _persistenceManager,
    );
    _serverInfoManager = ServerInfoManager();
    _deviceInfoManager = DeviceInfoManager();

    // Initialize lifecycle manager
    _lifecycleManager = ConnectionLifecycleManager(
      stateManager: _stateManager,
      serverInfoManager: _serverInfoManager,
      deviceInfoManager: _deviceInfoManager,
      persistence: _persistenceManager,
      onApiClientCreated: _onApiClientCreated,
      onDownloadLimitsChanged: _applyDownloadLimits,
    );

    // Initialize heartbeat manager
    _heartbeatManager = HeartbeatManager(
      stateManager: _stateManager,
      apiClientProvider: () async => _lifecycleManager.apiClient,
      deviceIdProvider: _deviceInfoManager.getDeviceId,
      isManualOfflineProvider: () async =>
          OfflinePlaybackService().isManualOfflineModeEnabled,
      tryRestoreConnection: tryRestoreConnection,
      onConnectionLoss: _handleConnectionLoss,
    );

    // Initialize WebSocket handler
    _webSocketHandler = WebSocketHandler(
      webSocketService: _webSocketService,
      onReconnect: _handleWebSocketReconnect,
      onDisconnect: _handleWebSocketDisconnect,
      onSessionInvalidated: _handleWebSocketSessionInvalidated,
      onSyncTokenAdvanced: _onSyncTokenAdvanced,
      deviceIdProvider: _deviceInfoManager.getDeviceId,
      deviceNameProvider: _deviceInfoManager.getDeviceName,
      sessionTokenProvider: () async => _authManager.sessionToken,
    );
    _webSocketHandler.messages.listen(_forwardWebSocketMessage);

    // Initialize endpoint switch handler
    _endpointSwitchHandler = EndpointSwitchHandler(
      endpointResolver: _serverInfoManager.endpointResolver,
      isServerReachable: (serverInfo) async {
        // Short timeout for quick check during switch
        return _lifecycleManager.isServerReachable(
          serverInfo,
          timeout: const Duration(milliseconds: 800),
        );
      },
      onSwitchEndpoint: _performEndpointSwitch,
      onRestoreAfterFailedSwitch: _restoreAfterFailedEndpointSwitch,
    );

    // Initialize library services
    _librarySyncEngine = LibrarySyncEngine(
      apiClientProvider: _requireApiClient,
      libraryRepository: _libraryRepository,
      onBootstrapCompleted: _onLocalBootstrapCompleted,
    );
    _libraryReadFacade = LibraryReadFacade(
      apiClientProvider: () => _lifecycleManager.apiClient,
      libraryRepository: _libraryRepository,
    );
  }

  // ============================================================================
  // PUBLIC GETTERS - Connection State
  // ============================================================================

  /// Check if connected to server
  bool get isConnected => _stateManager.isConnected;

  /// Get current API client
  ApiClient? get apiClient => _lifecycleManager.apiClient;

  /// Get current server info
  ServerInfo? get serverInfo => _stateManager.serverInfo;

  /// Get current session ID
  String? get sessionId => _lifecycleManager.sessionId;

  /// Get current session token (for authenticated requests)
  String? get sessionToken => _authManager.sessionToken;

  /// Get Authorization header map for authenticated requests
  Map<String, String>? get authHeaders => _authManager.authHeaders;

  /// Get current user ID
  String? get userId => _authManager.userId;

  /// Get current username
  String? get username => _authManager.username;

  /// Check if user is authenticated
  bool get isAuthenticated => _authManager.isAuthenticated;

  /// Get WebSocket and local sync message stream.
  Stream<WsMessage> get webSocketMessages => _messageController.stream;

  /// Unified library read facade for deterministic v1/v2 source selection
  LibraryReadFacade get libraryReadFacade => _libraryReadFacade;

  /// Stream of connection state changes (true = connected, false = disconnected)
  Stream<bool> get connectionStateStream => _stateManager.connectionStateStream;

  /// Stream of server info changes, including endpoint switches
  Stream<ServerInfo?> get serverInfoStream => _stateManager.serverInfoStream;

  /// Stream that emits when session expires (401 from server)
  Stream<void> get sessionExpiredStream => _authManager.sessionExpiredStream;

  /// Most recent reconnect failure code from [tryRestoreConnection], if any
  String? get lastRestoreFailureCode => _stateManager.lastRestoreFailureCode;

  /// Most recent reconnect failure message from [tryRestoreConnection], if any
  String? get lastRestoreFailureMessage =>
      _stateManager.lastRestoreFailureMessage;

  /// Most recent reconnect failure details from [tryRestoreConnection], if any
  Map<String, dynamic>? get lastRestoreFailureDetails =>
      _stateManager.lastRestoreFailureDetails;

  /// Whether the last restore failed due to authentication issues
  bool get didLastRestoreFailForAuth => _stateManager.didLastRestoreFailForAuth;

  /// Check if we have saved server info (even if not currently connected)
  bool get hasServerInfo => _stateManager.hasServerInfo;

  /// Resolve the current device display name used for server connections
  Future<String> getCurrentDeviceName() => _deviceInfoManager.getDeviceName();

  /// Resolve a server-relative media URL (for example `/api/artwork/...`)
  /// into an absolute URL using the current connected server.
  String? resolveServerUrl(String? url) {
    if (url == null || url.isEmpty) return url;

    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed.toString();
    }

    final baseUrl = _lifecycleManager.apiClient?.serverInfo.baseUrl ??
        _stateManager.serverInfo?.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      return url;
    }

    final baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    return baseUri.resolve(url).toString();
  }

  // ============================================================================
  // AUTHENTICATION
  // ============================================================================

  /// Register a new user account and connect to server
  Future<void> register({
    required String username,
    required String password,
    required ServerInfo serverInfo,
  }) async {
    final deviceId = await _deviceInfoManager.getDeviceId();
    final deviceName = await _deviceInfoManager.getDeviceName();

    // Resolve preferred server endpoint
    final resolvedServerInfo =
        await _serverInfoManager.resolvePreferredServerInfo(serverInfo);

    // Create API client
    final apiClient = ApiClient(
      serverInfo: resolvedServerInfo,
      deviceId: deviceId,
      deviceName: deviceName,
      onSessionExpired: handleSessionExpired,
    );

    // Update state
    _stateManager.setServerInfo(resolvedServerInfo);
    _applyDownloadLimits(resolvedServerInfo);

    // Test connection
    try {
      await apiClient.ping();
    } catch (e) {
      throw Exception('Cannot reach server: $e');
    }

    // Register user
    try {
      await apiClient.register(RegisterRequest(
        username: username,
        password: password,
      ));

      // Login immediately
      final loginResponse = await apiClient.login(LoginRequest(
        username: username,
        password: password,
        deviceId: deviceId,
        deviceName: deviceName,
      ));

      // Store auth info
      await _authManager.setAuthInfo(
        sessionToken: loginResponse.sessionToken,
        userId: loginResponse.userId,
        username: loginResponse.username,
      );

      // Set token on API client
      apiClient.sessionToken = loginResponse.sessionToken;

      // Complete connection
      await _completeAuthConnection(apiClient, resolvedServerInfo);
    } catch (e) {
      await _authManager.clearAuthInfo();
      rethrow;
    }
  }

  /// Login with username and password
  Future<void> login({
    required String username,
    required String password,
    required ServerInfo serverInfo,
  }) async {
    final deviceId = await _deviceInfoManager.getDeviceId();
    final deviceName = await _deviceInfoManager.getDeviceName();

    // Resolve preferred server endpoint
    final resolvedServerInfo =
        await _serverInfoManager.resolvePreferredServerInfo(serverInfo);

    // Create API client
    final apiClient = ApiClient(
      serverInfo: resolvedServerInfo,
      deviceId: deviceId,
      deviceName: deviceName,
      onSessionExpired: handleSessionExpired,
    );

    // Update state
    _stateManager.setServerInfo(resolvedServerInfo);
    _applyDownloadLimits(resolvedServerInfo);

    // Test connection
    try {
      await apiClient.ping();
    } catch (e) {
      throw Exception('Cannot reach server: $e');
    }

    // Login
    try {
      final response = await apiClient.login(LoginRequest(
        username: username,
        password: password,
        deviceId: deviceId,
        deviceName: deviceName,
      ));

      // Store auth info
      await _authManager.setAuthInfo(
        sessionToken: response.sessionToken,
        userId: response.userId,
        username: response.username,
      );

      // Set token on API client
      apiClient.sessionToken = response.sessionToken;

      // Complete connection
      await _completeAuthConnection(apiClient, resolvedServerInfo);
    } catch (e) {
      await _authManager.clearAuthInfo();
      rethrow;
    }
  }

  /// Logout and clear auth state
  Future<void> logout() async {
    final apiClient = _lifecycleManager.apiClient;
    final sessionToken = _authManager.sessionToken;
    final userId = _authManager.userId;

    if (apiClient != null && sessionToken != null) {
      try {
        await apiClient.logout(sessionToken);
      } catch (e) {
        // Ignore logout errors
      }
    }

    if (userId != null && userId.trim().isNotEmpty) {
      await LibraryPinStorage.migrateLegacyPinsToUser(userId);
      await PlaybackStateManager()
          .migrateLegacyCompletePlaybackStateToUser(userId);
    }

    await _authManager.clearAuthInfo();
    await disconnect(isManual: true);
  }

  /// Handle session expiry (called when server returns 401)
  Future<void> handleSessionExpired() async {
    await _authManager.handleSessionExpired();

    // Stop all services
    _endpointSwitchHandler.stopMonitoring();
    _librarySyncEngine.stop();
    _heartbeatManager.stop();
    _webSocketService.disconnect();
    _lifecycleManager.clearActiveConnection();

    // Update state
    _stateManager.resetConnectionState();
    _stateManager.setConnected(false);
  }

  /// Load stored auth info on app start
  Future<void> loadAuthInfo() async {
    await _authManager.loadAuthInfo();
  }

  // ============================================================================
  // CONNECTION MANAGEMENT
  // ============================================================================

  /// Connect to server using QR code data
  Future<void> connectFromQr(String qrData) async {
    await _lifecycleManager.connectFromQr(
      qrData,
      sessionToken: _authManager.sessionToken,
      onSessionExpired: handleSessionExpired,
    );
    await _onConnected();
  }

  /// Connect to server with ServerInfo
  Future<void> connectToServer(ServerInfo serverInfo) async {
    await _lifecycleManager.connectToServer(
      serverInfo,
      sessionToken: _authManager.sessionToken,
      onSessionExpired: handleSessionExpired,
    );
    await _onConnected();
  }

  /// Disconnect from server
  Future<void> disconnect({bool isManual = false}) async {
    await _lifecycleManager.disconnect(isManual: isManual);
    await _onDisconnected();
  }

  /// Try to restore previous connection
  Future<bool> tryRestoreConnection() async {
    final inFlight = _restoreConnectionInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final restoreFuture = _tryRestoreConnectionInternal();
    _restoreConnectionInFlight = restoreFuture;

    try {
      return await restoreFuture;
    } finally {
      if (identical(_restoreConnectionInFlight, restoreFuture)) {
        _restoreConnectionInFlight = null;
      }
    }
  }

  Future<bool> _tryRestoreConnectionInternal() async {
    final restored = await _lifecycleManager.tryRestoreConnection(
      sessionToken: _authManager.sessionToken,
      onSessionExpired: handleSessionExpired,
    );

    if (restored) {
      await _onConnected();
    } else {
      if (_stateManager.didLastRestoreFailForAuth &&
          _authManager.sessionToken == null) {
        await handleSessionExpired();
      } else {
        await _onDisconnected();
      }
    }

    return restored;
  }

  /// Load server info from storage without attempting connection
  Future<void> loadServerInfoFromStorage() async {
    await _lifecycleManager.loadServerInfoFromStorage();
  }

  // ============================================================================
  // PRIVATE METHODS - Connection Lifecycle
  // ============================================================================

  Future<void> _completeAuthConnection(
    ApiClient apiClient,
    ServerInfo serverInfo,
  ) async {
    final deviceId = await _deviceInfoManager.getDeviceId();
    final deviceName = await _deviceInfoManager.getDeviceName();

    // Send connect request
    final response = await apiClient.connect(ConnectRequest(
      deviceId: deviceId,
      deviceName: deviceName,
      appVersion: '4.3.0',
      platform: Platform.isAndroid ? 'android' : 'ios',
    ));

    // Apply device ID from server
    if (response.deviceId != null && response.deviceId != deviceId) {
      await _deviceInfoManager.saveDeviceId(response.deviceId!);
    }

    // Hydrate server metadata
    final hydratedServerInfo =
        await _serverInfoManager.hydrateServerInfoMetadata(
      apiClient,
      serverInfo,
    );

    _lifecycleManager.adoptEstablishedConnection(
      apiClient: apiClient,
      sessionId: response.sessionId,
      serverInfo: hydratedServerInfo,
    );
    _applyDownloadLimits(hydratedServerInfo);
    await _persistenceManager.saveConnectionInfo(
      hydratedServerInfo,
      response.sessionId,
    );

    // Update state
    _stateManager.setServerInfo(hydratedServerInfo);
    _stateManager.setConnected(true);
    _stateManager.setManuallyDisconnected(false);
    _stateManager.clearRestoreFailure();

    // Start services
    await _onConnected();
  }

  Future<void> _onConnected() async {
    final serverInfo = _stateManager.serverInfo;
    if (serverInfo == null) return;

    // Notify offline service
    await OfflinePlaybackService().notifyConnectionRestored();

    // Start heartbeat
    _heartbeatManager.start();

    // Connect WebSocket
    await _webSocketHandler.connect(serverInfo);

    // Start library sync
    _librarySyncEngine.start();

    // Start endpoint monitoring
    _endpointSwitchHandler.configureMonitoring(serverInfo);
  }

  Future<void> _onDisconnected() async {
    _endpointSwitchHandler.stopMonitoring();
    _librarySyncEngine.stop();
    _heartbeatManager.stop();
    _webSocketService.disconnect();

    // Notify offline service
    await OfflinePlaybackService().notifyConnectionLost();
  }

  // ============================================================================
  // PRIVATE METHODS - Event Handlers
  // ============================================================================

  void _onApiClientCreated(ApiClient apiClient) {
    // Store reference if needed for legacy code
  }

  void _applyDownloadLimits(ServerInfo serverInfo) {
    final limits = serverInfo.downloadLimits;
    DownloadManager().setMaxConcurrentDownloads(limits.maxConcurrentPerUser);
  }

  Future<void> _handleWebSocketReconnect() async {
    // Ensure identified
    await _webSocketHandler.sendIdentify();

    // If already connected, just sync
    if (_stateManager.isConnected) {
      unawaited(_librarySyncEngine.syncNow());
      return;
    }

    // Try to restore full connection
    await tryRestoreConnection();
  }

  Future<void> _handleWebSocketDisconnect() async {
    if (_stateManager.isConnected) {
      _endpointSwitchHandler.stopMonitoring();
      _librarySyncEngine.stop();
      _lifecycleManager.clearActiveConnection();
      _stateManager.setConnected(false);

      await OfflinePlaybackService().notifyConnectionLost();
      _stateManager.setConnected(false);
    }
  }

  Future<void> _handleWebSocketSessionInvalidated(
    int? closeCode,
    String? closeReason,
  ) async {
    // closeCode/closeReason are currently informational; force standard
    // session-expired handling to clear auth and route user to login.
    await handleSessionExpired();
  }

  Future<void> _handleConnectionLoss() async {
    _endpointSwitchHandler.stopMonitoring();
    _librarySyncEngine.stop();
    _lifecycleManager.clearActiveConnection();
    _stateManager.setConnected(false);

    await OfflinePlaybackService().notifyConnectionLost();
    _stateManager.setConnected(false);
  }

  Future<void> _onSyncTokenAdvanced(int latestToken) async {
    await _librarySyncEngine.syncUntil(latestToken);
  }

  Future<void> _onLocalBootstrapCompleted(int latestToken) async {
    if (_messageController.isClosed) return;
    _messageController.add(
      SyncTokenAdvancedMessage(
        latestToken: latestToken,
        reason: 'bootstrap_complete',
      ),
    );
  }

  void _forwardWebSocketMessage(WsMessage message) {
    if (_messageController.isClosed) return;
    _messageController.add(message);
  }

  Future<void> _performEndpointSwitch(ServerInfo newServerInfo) async {
    // Stop current services
    _librarySyncEngine.stop();
    _webSocketService.disconnect();
    _heartbeatManager.stop();

    // Create new API client with new endpoint
    final deviceId = await _deviceInfoManager.getDeviceId();
    final deviceName = await _deviceInfoManager.getDeviceName();

    final apiClient = ApiClient(
      serverInfo: newServerInfo,
      deviceId: deviceId,
      deviceName: deviceName,
      sessionToken: _authManager.sessionToken,
      onSessionExpired: handleSessionExpired,
    );

    await apiClient.ping();

    final response = await apiClient.connect(ConnectRequest(
      deviceId: deviceId,
      deviceName: deviceName,
      appVersion: '4.3.0',
      platform: Platform.isAndroid ? 'android' : 'ios',
    ));

    if (response.deviceId != null) {
      await _deviceInfoManager.saveDeviceId(response.deviceId!);
    }

    final hydratedServerInfo =
        await _serverInfoManager.hydrateServerInfoMetadata(
      apiClient,
      newServerInfo,
    );

    _stateManager.setServerInfo(hydratedServerInfo);
    _stateManager.setConnected(true);

    await _persistenceManager.saveConnectionInfo(
      hydratedServerInfo,
      response.sessionId,
    );

    // Restart services
    _heartbeatManager.start();
    await _webSocketHandler.connect(hydratedServerInfo);
    _librarySyncEngine.start();
    _endpointSwitchHandler.configureMonitoring(hydratedServerInfo);
  }

  Future<void> _restoreAfterFailedEndpointSwitch(
      ServerInfo originalServerInfo) async {
    try {
      await _performEndpointSwitch(originalServerInfo);
    } catch (e) {
      await _handleConnectionLoss();
    }
  }

  ApiClient _requireApiClient() {
    final client = _lifecycleManager.apiClient;
    if (client == null) {
      throw StateError('API client unavailable for sync operation');
    }
    return client;
  }
}
