import 'dart:async';
import 'dart:io';
import '../../../models/api_models.dart';
import '../../../models/server_info.dart';
import '../../../utils/qr_payload_parser.dart';
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

  ApiClient? get apiClient => _apiClient;

  String? get sessionId => _sessionId;

  /// Adopt an already-authenticated connection created outside this manager.
  void adoptEstablishedConnection({
    required ApiClient apiClient,
    required String sessionId,
    required ServerInfo serverInfo,
  }) {
    if (!identical(_apiClient, apiClient)) {
      _apiClient?.close();
    }
    _apiClient = apiClient;
    _sessionId = sessionId;
    _stateManager.setServerInfo(serverInfo);
    _serverInfoManager.setServerInfo(serverInfo);
  }

  /// Clear the active client/session while keeping server info for reconnects.
  void clearActiveConnection() {
    _cleanupConnection();
  }

  Future<void> connectFromQr(
    String qrData, {
    String? sessionToken,
    void Function()? onSessionExpired,
  }) async {
    // Parse strictly and separately from connecting, so a connection failure
    // isn't mislabeled as a bad QR code. The error must never include the
    // payload: it may carry a registration token.
    final parsed = QrPayloadParser.parse(qrData);
    if (!parsed.isValid) {
      throw Exception('Invalid QR code format');
    }
    await connectToServer(
      parsed.serverInfo!,
      sessionToken: sessionToken,
      onSessionExpired: onSessionExpired,
    );
  }

  Future<void> connectToServer(
    ServerInfo serverInfo, {
    String? sessionToken,
    void Function()? onSessionExpired,
  }) async {
    final deviceId = await _deviceInfoManager.getDeviceId();
    final deviceName = await _deviceInfoManager.getDeviceName();

    final resolvedServerInfo =
        await _serverInfoManager.resolvePreferredServerInfo(serverInfo);

    _apiClient = ApiClient(
      serverInfo: resolvedServerInfo,
      deviceId: deviceId,
      deviceName: deviceName,
      sessionToken: sessionToken,
      onSessionExpired: onSessionExpired,
    );
    _onApiClientCreated?.call(_apiClient!);

    _stateManager.setServerInfo(resolvedServerInfo);
    _serverInfoManager.setServerInfo(resolvedServerInfo);
    _onDownloadLimitsChanged?.call(resolvedServerInfo);

    try {
      await _apiClient!.ping();
    } catch (e) {
      _cleanupConnection();
      throw Exception('Cannot reach server: $e');
    }

    final connectRequest = ConnectRequest(
      deviceId: deviceId,
      deviceName: deviceName,
      appVersion: '5.0 Preview',
      platform: Platform.isAndroid ? 'android' : 'ios',
    );

    try {
      final response = await _apiClient!.connect(connectRequest);

      if (response.deviceId != null && response.deviceId != deviceId) {
        await _deviceInfoManager.saveDeviceId(response.deviceId!);
      }

      final hydratedServerInfo =
          await _serverInfoManager.hydrateServerInfoMetadata(
        _apiClient!,
        resolvedServerInfo,
      );

      _sessionId = response.sessionId;
      _stateManager.setServerInfo(hydratedServerInfo);
      _serverInfoManager.setServerInfo(hydratedServerInfo);
      _onDownloadLimitsChanged?.call(hydratedServerInfo);
      _stateManager.setConnected(true);
      _stateManager.setManuallyDisconnected(false);
      _stateManager.clearRestoreFailure();

      await _persistence.saveConnectionInfo(hydratedServerInfo, _sessionId!);
      await _persistence.saveDeviceId(response.deviceId ?? deviceId);

      return;
    } catch (e) {
      _cleanupConnection();
      throw Exception('Connection failed: $e');
    }
  }

  Future<void> disconnect({bool isManual = false}) async {
    _stateManager.setManuallyDisconnected(isManual);

    if (_apiClient != null && _stateManager.isConnected) {
      try {
        final request = DisconnectRequest(deviceId: _apiClient!.deviceId);
        // Best-effort notify: don't let an unreachable server hold up the
        // local disconnect for the full HTTP timeout.
        await _apiClient!
            .disconnect(request)
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        // Ignore disconnect errors
      }
    }

    _cleanupConnection();
    _stateManager.setConnected(false);
  }

  Future<bool> tryRestoreConnection({
    String? sessionToken,
    void Function()? onSessionExpired,
  }) async {
    _stateManager.clearRestoreFailure();

    final serverInfo = await _persistence.loadServerInfo();
    if (serverInfo == null) {
      return false;
    }

    final resolvedServerInfo =
        await _serverInfoManager.resolvePreferredServerInfo(serverInfo);
    _onDownloadLimitsChanged?.call(resolvedServerInfo);

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

      _stateManager.setServerInfo(resolvedServerInfo);
      _serverInfoManager.setServerInfo(resolvedServerInfo);

      await _apiClient!.ping();

      final connectRequest = ConnectRequest(
        deviceId: deviceId,
        deviceName: deviceName,
        appVersion: '5.0 Preview',
        platform: Platform.isAndroid ? 'android' : 'ios',
      );

      final response = await _apiClient!.connect(connectRequest);

      if (response.deviceId != null && response.deviceId != deviceId) {
        await _deviceInfoManager.saveDeviceId(response.deviceId!);
      }

      final hydratedServerInfo =
          await _serverInfoManager.hydrateServerInfoMetadata(
        _apiClient!,
        resolvedServerInfo,
      );

      _sessionId = response.sessionId;
      _stateManager.setServerInfo(hydratedServerInfo);
      _serverInfoManager.setServerInfo(hydratedServerInfo);
      _onDownloadLimitsChanged?.call(hydratedServerInfo);
      _stateManager.setConnected(true);
      _stateManager.setManuallyDisconnected(false);
      _stateManager.clearRestoreFailure();

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

  void _cleanupConnection() {
    _apiClient?.close();
    _apiClient = null;
    _sessionId = null;
  }

  void dispose() {
    _cleanupConnection();
  }
}
