part of '../http_server.dart';

extension AriamiHttpServerWebSocketAndStaticMethods on AriamiHttpServer {
  /// Maps WebSocket identify + device metadata to a presence [clientType]
  /// so CLI/desktop dashboards are not counted as mobile in `/api/stats`.
  String? _effectivePresenceClientType({
    required String deviceId,
    String? deviceName,
    String? wsClientType,
  }) {
    if (wsClientType == 'dashboard') {
      return 'dashboard';
    }
    final name = deviceName ?? 'Unknown Device';
    if (AuthService.isDashboardControlDevice(
        deviceId: deviceId, deviceName: name)) {
      return 'dashboard';
    }
    return wsClientType;
  }

  /// Handle WebSocket connection
  void _handleWebSocket(WebSocketChannel webSocket, String? subprotocol) {
    print(
        'WebSocket client connected; waiting for identify (${_webSocketClients.length} active)');

    webSocket.stream.listen(
      (message) {
        _handleWebSocketMessage(webSocket, message);
      },
      onDone: () {
        _webSocketClients.remove(webSocket);
        _connectHub.unregister(webSocket);
        final deviceId = _untrackWebSocketDevice(webSocket);
        if (deviceId == null) {
          print(
              'WebSocket disconnected without identify - no client to unregister');
        }
        print(
            'WebSocket client disconnected (${_webSocketClients.length} remaining)');
      },
      onError: (error) {
        _webSocketClients.remove(webSocket);
        _connectHub.unregister(webSocket);
        final deviceId = _untrackWebSocketDevice(webSocket);
        if (deviceId == null) {
          print('WebSocket error without identify - no client to unregister');
        }
        print('WebSocket error: $error');
      },
    );
  }

  void _trackWebSocketClient(WebSocketChannel webSocket) {
    if (!_webSocketClients.contains(webSocket)) {
      _webSocketClients.add(webSocket);
    }
  }

  /// A playback client may own both the library-sync and Connect sockets.
  /// Presence is removed only after its final socket closes.
  String? _untrackWebSocketDevice(WebSocketChannel webSocket) {
    final deviceId = _webSocketDeviceIds.remove(webSocket);
    if (deviceId != null && !_webSocketDeviceIds.containsValue(deviceId)) {
      _connectionManager.unregisterClient(deviceId);
    }
    return deviceId;
  }

  /// Handle incoming WebSocket message
  void _handleWebSocketMessage(WebSocketChannel webSocket, dynamic rawMessage) {
    try {
      final jsonMessage =
          jsonDecode(rawMessage as String) as Map<String, dynamic>;
      final message = WsMessage.fromJson(jsonMessage);

      print('WebSocket message received: ${message.type}');

      // Handle identify
      if (message.type == WsMessageType.identify) {
        final identifyMsg = IdentifyMessage.fromWsMessage(message);
        final deviceId = identifyMsg.deviceId;
        final deviceName = identifyMsg.deviceName;
        final sessionToken = identifyMsg.sessionToken;
        final clientType = identifyMsg.clientType;

        // Validate session token once an owner account exists.
        if (_hasRegisteredUsers()) {
          if (sessionToken == null || sessionToken.isEmpty) {
            // Close WebSocket with code 4001 (auth required)
            webSocket.sink.close(4001, 'Authentication required');
            return;
          }

          // Validate session token asynchronously
          _authService.validateSession(sessionToken).then((session) {
            if (session == null) {
              // Close WebSocket with code 4001 (invalid session)
              webSocket.sink.close(4001, 'Session expired or invalid');
              return;
            }

            // Session valid - register or refresh client (upgrade clientType)
            if (deviceId.isNotEmpty) {
              _trackWebSocketClient(webSocket);
              _webSocketDeviceIds[webSocket] = deviceId;
              final effectiveType = _effectivePresenceClientType(
                deviceId: deviceId,
                deviceName: deviceName,
                wsClientType: clientType,
              );
              _connectionManager.registerOrRefreshClient(
                deviceId,
                deviceName ?? 'Unknown Device',
                userId: session.userId,
                clientType: effectiveType,
              );
              if (const {'desktop', 'mobile', 'tv'}.contains(clientType)) {
                _connectHub.register(
                  webSocket,
                  userId: session.userId,
                  deviceId: deviceId,
                  deviceName: deviceName ?? 'Unknown Device',
                  clientType: clientType!,
                );
              }
            }
          });
          return;
        }

        // First-run bootstrap mode - no auth required.
        if (deviceId.isNotEmpty) {
          _trackWebSocketClient(webSocket);
          _webSocketDeviceIds[webSocket] = deviceId;
          final effectiveType = _effectivePresenceClientType(
            deviceId: deviceId,
            deviceName: deviceName,
            wsClientType: clientType,
          );
          _connectionManager.registerOrRefreshClient(
            deviceId,
            deviceName ?? 'Unknown Device',
            clientType: effectiveType,
          );
          if (const {'desktop', 'mobile', 'tv'}.contains(clientType)) {
            _connectHub.register(
              webSocket,
              userId: 'legacy',
              deviceId: deviceId,
              deviceName: deviceName ?? 'Unknown Device',
              clientType: clientType!,
            );
          }
        }
        return;
      }

      // Handle ping
      if (message.type == WsMessageType.ping) {
        final deviceId = _webSocketDeviceIds[webSocket];
        if (deviceId != null && deviceId.isNotEmpty) {
          _connectionManager.refreshHeartbeatIfRegistered(deviceId);
        }
        _sendWebSocketMessage(webSocket, PongMessage());
        return;
      }

      if (_connectHub.handle(webSocket, message)) {
        return;
      }

      // Other message types can be handled here in future phases
    } catch (e) {
      print('Error parsing WebSocket message: $e');
    }
  }

  /// Send message to a specific WebSocket client
  void _sendWebSocketMessage(WebSocketChannel webSocket, WsMessage message) {
    try {
      final jsonString = jsonEncode(message.toJson());
      webSocket.sink.add(jsonString);
    } catch (e) {
      print('Error sending WebSocket message: $e');
    }
  }

  /// Broadcast message to all connected WebSocket clients
  void broadcastWebSocketMessage(WsMessage message) {
    print(
        'Broadcasting ${message.type} to ${_webSocketClients.length} clients');
    for (final client in List.from(_webSocketClients)) {
      _sendWebSocketMessage(client, message);
    }
  }

  /// Notify clients about library update
  void notifyLibraryUpdated({int? albumCount, int? songCount}) {
    final message = LibraryUpdatedMessage(
      data: {
        if (albumCount != null) 'albumCount': albumCount,
        if (songCount != null) 'songCount': songCount,
      },
    );
    broadcastWebSocketMessage(message);
  }

  /// Notify clients that sync token advanced for incremental v2 sync.
  void notifySyncTokenAdvanced({
    required int latestToken,
    required String reason,
  }) {
    _lastBroadcastSyncToken = latestToken;
    final message = SyncTokenAdvancedMessage(
      latestToken: latestToken,
      reason: reason,
    );
    broadcastWebSocketMessage(message);
  }

  /// Start timer to cleanup stale connections
  void _startCleanupTimer() {
    Future.delayed(const Duration(seconds: 30), () {
      if (_server != null) {
        _cleanupStaleConnectionsWithBroadcast();
        _startCleanupTimer();
      }
    });
  }

  /// Cleanup stale connections and broadcast to WebSocket clients if any were removed
  void _cleanupStaleConnectionsWithBroadcast() {
    final beforeCount = _connectionManager.clientCount;
    _connectionManager.cleanupStaleConnections();
    final afterCount = _connectionManager.clientCount;

    // Broadcast if any clients were removed
    if (afterCount < beforeCount) {
      broadcastWebSocketMessage(ClientDisconnectedMessage(
        clientCount: afterCount,
        deviceName: null, // Unknown which specific client was removed
      ));
    }
  }

  /// Create static file handler for serving web assets
  Handler _createStaticHandler() {
    return createStaticHandler(
      _webAssetsPath!,
      defaultDocument: 'index.html',
      listDirectories: false,
    );
  }

  /// Fallback handler when no web assets are configured
  Handler _notFoundHandler() {
    return (Request request) {
      return Response.notFound('Not found');
    };
  }
}
