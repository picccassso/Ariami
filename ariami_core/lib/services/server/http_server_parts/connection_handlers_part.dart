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
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final rawDeviceId = data['deviceId'] as String?;
      final rawDeviceName = data['deviceName'] as String?;

      final deviceName = (rawDeviceName == null || rawDeviceName.isEmpty)
          ? 'Unknown Device'
          : rawDeviceName;

      String deviceId = rawDeviceId?.trim() ?? '';
      if (deviceId.isEmpty || deviceId == 'unknown-device') {
        deviceId = _generateDeviceId();
      }

      final session = request.context['session'] as Session?;
      final userId = session?.userId;

      _connectionManager.registerOrRefreshClient(
        deviceId,
        deviceName,
        userId: userId,
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
        'serverVersion': '4.1.0',
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

  /// Handle client disconnection.
  /// In auth mode, uses bearer session context.
  /// In legacy mode, expects deviceId in request body.
  Future<Response> _handleDisconnect(Request request) async {
    try {
      final body = await request.readAsString();
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      final deviceId = data['deviceId'] as String?;
      final session = request.context['session'] as Session?;

      late final String resolvedDeviceId;
      String? deviceName;

      if (_authRequired && !_legacyMode) {
        if (session == null) {
          return _jsonUnauthorized({
            'error': {
              'code': AuthErrorCodes.authRequired,
              'message': 'Not authenticated',
            },
          });
        }

        resolvedDeviceId = session.deviceId;
        // Disconnect is a presence change only - do NOT revoke auth session
        // or stream tickets. Session remains valid for reconnection.
        // Explicit logout (/api/auth/logout) and admin actions still revoke.
      } else {
        if (deviceId == null || deviceId.isEmpty) {
          return _jsonBadRequest({
            'error': 'Missing required field',
            'message': 'deviceId is required',
          });
        }
        resolvedDeviceId = deviceId;
      }

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
