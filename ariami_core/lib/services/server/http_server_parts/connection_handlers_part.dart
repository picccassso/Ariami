part of '../http_server.dart';

extension AriamiHttpServerConnectionHandlersMethods on AriamiHttpServer {
  String _generateDeviceId() {
    final nonce = _generateHexNonce(8);
    return 'device_${DateTime.now().millisecondsSinceEpoch}_$nonce';
  }

  String _generateHexNonce(int byteCount) {
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      final byte = _secureRandom.nextInt(256);
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Handle client connection
  Future<Response> _handleConnect(Request request) async {
    try {
      if (!_hasRegisteredUsers()) {
        return _authRequiredResponse();
      }
      final session = request.context['session'] as Session?;
      if (session == null) {
        return _authRequiredResponse();
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final rawDeviceId = data['deviceId'] as String?;
      final rawDeviceName = data['deviceName'] as String?;

      final reportedName = (rawDeviceName == null || rawDeviceName.isEmpty)
          ? 'Unknown Device'
          : rawDeviceName;

      String deviceId = rawDeviceId?.trim() ?? '';
      if (deviceId.isEmpty || deviceId == 'unknown-device') {
        deviceId = _generateDeviceId();
      }

      final userId = session.userId;

      // Classification uses the reported name; display uses any custom name.
      final presenceClientType = AuthService.isDashboardControlDevice(
              deviceId: deviceId, deviceName: reportedName)
          ? 'dashboard'
          : null;
      final deviceName = _effectiveDeviceName(deviceId, reportedName);
      _connectionManager.registerOrRefreshClient(
        deviceId,
        deviceName,
        userId: userId,
        clientType: presenceClientType,
      );

      // Broadcast client connection to all WebSocket clients
      broadcastWebSocketMessage(ClientConnectedMessage(
        clientCount: _connectionManager.clientCount,
        deviceName: deviceName,
      ));

      // Generate session ID
      final sessionId =
          'session_${DateTime.now().millisecondsSinceEpoch}_$deviceId';

      return _jsonOk({
        'status': 'connected',
        'sessionId': sessionId,
        'serverVersion': kAriamiVersion,
        'features': ['library', 'streaming', 'websocket'],
        'deviceId': deviceId,
      });
    } catch (e) {
      return _jsonBadRequest({
        'error': 'Invalid request',
        'message': e.toString(),
      });
    }
  }

  /// Handle client disconnection using bearer session context.
  Future<Response> _handleDisconnect(Request request) async {
    try {
      final session = request.context['session'] as Session?;

      late final String resolvedDeviceId;
      String? deviceName;

      if (!_hasRegisteredUsers() || session == null) {
        return _authRequiredResponse();
      }

      resolvedDeviceId = session.deviceId;
      // Disconnect is a presence change only - do NOT revoke auth session
      // or stream tickets. Session remains valid for reconnection.
      // Explicit logout (/api/auth/logout) and admin actions still revoke.

      // Get client name before unregistering
      final client = _connectionManager.getClient(resolvedDeviceId);
      deviceName = client?.deviceName;
      _connectionManager.unregisterClient(resolvedDeviceId);

      // Broadcast client disconnection to all WebSocket clients
      broadcastWebSocketMessage(ClientDisconnectedMessage(
        clientCount: _connectionManager.clientCount,
        deviceName: deviceName,
      ));

      return _jsonOk({
        'status': 'disconnected',
        'deviceId': resolvedDeviceId,
      });
    } catch (e) {
      return _jsonBadRequest({
        'error': 'Invalid request',
        'message': e.toString(),
      });
    }
  }
}
