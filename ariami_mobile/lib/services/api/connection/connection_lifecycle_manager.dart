import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../models/api_models.dart';
import '../../../models/server_info.dart';
import '../api_client.dart';
import 'connection_persistence_manager.dart';
import 'connection_state_manager.dart';
import 'device_info_manager.dart';
import 'server_info_manager.dart';

/// Manages the connection lifecycle: connect, disconnect, and restore.
///
/// This is a complex module that coordinates multiple steps:
/// - Creating and configuring the API client
/// - Testing connectivity
/// - Sending connect/disconnect requests
/// - Hydrating server metadata
/// - Saving/restoring connection info
class ConnectionLifecycleManager {
  final ConnectionStateManager _stateManager;
  final ServerInfoManager _serverInfoManager;
  final DeviceInfoManager _deviceInfoManager;
  final ConnectionPersistenceManager _persistence;
  final void Function(ApiClient apiClient)? _onApiClientCreated;
  final void Function(ServerInfo)? _onDownloadLimitsChanged;

  ApiClient? _apiClient;
  String? _sessionId;

  /// Creates a ConnectionLifecycleManager.
  ConnectionLifecycleManager({
    required ConnectionStateManager stateManager,
    required ServerInfoManager serverInfoManager,
    required DeviceInfoManager deviceInfoManager,
    required ConnectionPersistenceManager persistence,
    void Function(ApiClient apiClient)? onApiClientCreated,
    void Function(ServerInfo)? onDownloadLimitsChanged,
  })  : _stateManager = stateManager,
        _serverInfoManager = serverInfoManager,
        _deviceInfoManager = deviceInfoManager,
        _persistence = persistence,
        _onApiClientCreated = onApiClientCreated,
        _onDownloadLimitsChanged = onDownloadLimitsChanged;

  /// Current API client instance
  ApiClient? get apiClient => _apiClient;

  /// Current session ID
  String? get sessionId => _sessionId;

  /// Adopt an already-authenticated connection created outside this manager.
  void adoptEstablishedConnection({
    required ApiClient apiClient,
    required String sessionId,
    required ServerInfo serverInfo,
  }) {
    _apiClient = apiClient;
    _sessionId = sessionId;
    _stateManager.setServerInfo(serverInfo);
    _serverInfoManager.setServerInfo(serverInfo);
  }

  /// Clear the active client/session while keeping server info for reconnects.
  void clearActiveConnection() {
    _cleanupConnection();
  }

  /// Connect to server using QR code data (JSON string)
  Future<void> connectFromQr(
    String qrData, {
    String? sessionToken,
    void Function()? onSessionExpired,
  }) async {
    try {
      final serverInfo = ServerInfo.fromJson(
        Map<String, dynamic>.from(
          const JsonDecoder().convert(qrData) as Map,
        ),
      );
      await connectToServer(
        serverInfo,
        sessionToken: sessionToken,
        onSessionExpired: onSessionExpired,
      );
    } catch (e) {
      throw Exception('Invalid QR code format: $e');
    }
  }

  /// Connect to server with ServerInfo
  Future<void> connectToServer(
    ServerInfo serverInfo, {
    String? sessionToken,
    void Function()? onSessionExpired,
  }) async {
    final deviceId = await _deviceInfoManager.getDeviceId();
    final deviceName = await _deviceInfoManager.getDeviceName();

    // Resolve preferred endpoint (LAN vs Tailscale)
    final resolvedServerInfo =
        await _serverInfoManager.resolvePreferredServerInfo(serverInfo);

    // Create API client
    _apiClient = ApiClient(
      serverInfo: resolvedServerInfo,
      deviceId: deviceId,
      deviceName: deviceName,
      sessionToken: sessionToken,
      onSessionExpired: onSessionExpired,
    );
    _onApiClientCreated?.call(_apiClient!);

    // Update state
    _stateManager.setServerInfo(resolvedServerInfo);
    _serverInfoManager.setServerInfo(resolvedServerInfo);
    _onDownloadLimitsChanged?.call(resolvedServerInfo);

    // Test connection with ping
    try {
      await _apiClient!.ping();
    } catch (e) {
      _cleanupConnection();
      throw Exception('Cannot reach server: $e');
    }

    // Send connect request
    final connectRequest = ConnectRequest(
      deviceId: deviceId,
      deviceName: deviceName,
      appVersion: '4.0.0',
      platform: Platform.isAndroid ? 'android' : 'ios',
    );

    try {
      final response = await _apiClient!.connect(connectRequest);

      // Apply device ID from server if different
      if (response.deviceId != null && response.deviceId != deviceId) {
        await _deviceInfoManager.saveDeviceId(response.deviceId!);
      }

      // Hydrate server metadata
      final hydratedServerInfo =
          await _serverInfoManager.hydrateServerInfoMetadata(
        _apiClient!,
        resolvedServerInfo,
      );

      // Update state
      _sessionId = response.sessionId;
      _stateManager.setServerInfo(hydratedServerInfo);
      _serverInfoManager.setServerInfo(hydratedServerInfo);
      _stateManager.setConnected(true);
      _stateManager.setManuallyDisconnected(false);
      _stateManager.clearRestoreFailure();

      // Persist connection info
      await _persistence.saveConnectionInfo(hydratedServerInfo, _sessionId!);
      await _persistence.saveDeviceId(response.deviceId ?? deviceId);

      return;
    } catch (e) {
      _cleanupConnection();
      throw Exception('Connection failed: $e');
    }
  }

  /// Disconnect from server
  Future<void> disconnect({bool isManual = false}) async {
    _stateManager.setManuallyDisconnected(isManual);

    if (_apiClient != null && _stateManager.isConnected) {
      try {
        final request = DisconnectRequest(deviceId: _apiClient!.deviceId);
        await _apiClient!.disconnect(request);
      } catch (e) {
        // Ignore disconnect errors
      }
    }

    _cleanupConnection();
    _stateManager.setConnected(false);
  }

  /// Try to restore previous connection
  Future<bool> tryRestoreConnection({
    String? sessionToken,
    void Function()? onSessionExpired,
  }) async {
    _stateManager.clearRestoreFailure();

    final serverInfo = await _persistence.loadServerInfo();
    if (serverInfo == null) {
      return false;
    }

    // Resolve preferred endpoint
    final resolvedServerInfo =
        await _serverInfoManager.resolvePreferredServerInfo(serverInfo);
    _onDownloadLimitsChanged?.call(resolvedServerInfo);

    // Quick reachability check first
    if (!await isServerReachable(resolvedServerInfo)) {
      _stateManager.setServerInfo(serverInfo);
      return false;
    }

    try {
      final deviceId = await _deviceInfoManager.getDeviceId();
      final deviceName = await _deviceInfoManager.getDeviceName();

      // Create API client with shorter timeout for restore
      _apiClient = ApiClient(
        serverInfo: resolvedServerInfo,
        timeout: const Duration(seconds: 3),
        deviceId: deviceId,
        deviceName: deviceName,
        sessionToken: sessionToken,
        onSessionExpired: onSessionExpired,
      );
      _onApiClientCreated?.call(_apiClient!);

      // Update state
      _stateManager.setServerInfo(resolvedServerInfo);
      _serverInfoManager.setServerInfo(resolvedServerInfo);

      // Test connectivity
      await _apiClient!.ping();

      // Re-register with server
      final connectRequest = ConnectRequest(
        deviceId: deviceId,
        deviceName: deviceName,
        appVersion: '4.0.0',
        platform: Platform.isAndroid ? 'android' : 'ios',
      );

      final response = await _apiClient!.connect(connectRequest);

      // Apply device ID from server
      if (response.deviceId != null && response.deviceId != deviceId) {
        await _deviceInfoManager.saveDeviceId(response.deviceId!);
      }

      // Hydrate server metadata
      final hydratedServerInfo =
          await _serverInfoManager.hydrateServerInfoMetadata(
        _apiClient!,
        resolvedServerInfo,
      );

      // Update state
      _sessionId = response.sessionId;
      _stateManager.setServerInfo(hydratedServerInfo);
      _serverInfoManager.setServerInfo(hydratedServerInfo);
      _stateManager.setConnected(true);
      _stateManager.setManuallyDisconnected(false);
      _stateManager.clearRestoreFailure();

      // Persist
      await _persistence.saveConnectionInfo(hydratedServerInfo, _sessionId!);

      return true;
    } on ApiException catch (e) {
      _stateManager.setRestoreFailure(
        code: e.code,
        message: e.message,
        details: e.details,
      );
      _cleanupConnection();
      return false;
    } catch (e) {
      _stateManager.setRestoreFailure(
        code: 'SERVER_ERROR',
        message: e.toString(),
      );
      _cleanupConnection();
      return false;
    }
  }

  /// Check if server is reachable at TCP level
  Future<bool> isServerReachable(
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
      return false;
    }
  }

  /// Load server info from storage without attempting connection
  Future<void> loadServerInfoFromStorage() async {
    final serverInfo = await _persistence.loadServerInfo();

    if (serverInfo != null) {
      _stateManager.setServerInfo(serverInfo);
      _serverInfoManager.setServerInfo(serverInfo);
      _onDownloadLimitsChanged?.call(serverInfo);
    } else if (!_stateManager.isConnected) {
      _stateManager.setServerInfo(null);
      _serverInfoManager.setServerInfo(null);
    }
  }

  /// Clean up connection state
  void _cleanupConnection() {
    _apiClient = null;
    _sessionId = null;
  }

  /// Dispose resources
  void dispose() {
    _cleanupConnection();
  }
}
