part of '../http_server.dart';

extension AriamiHttpServerWebSocketAndStaticMethods on AriamiHttpServer {
  /// The display name to use for a device: a user-chosen custom name when one
  /// is stored, else the name the client reported. Presence *classification*
  /// deliberately keeps using the reported name — renaming a phone to
  /// "Ariami Desktop Dashboard" must not change how it is counted.
  String? _customOrReportedDeviceName(String deviceId, String? reported) {
    final custom = _deviceNameStore.isInitialized
        ? _deviceNameStore.nameFor(deviceId)
        : null;
    return custom ?? reported;
  }

  /// Like [_customOrReportedDeviceName], with the registration fallback.
  String _effectiveDeviceName(String deviceId, String? reported) {
    final name = _customOrReportedDeviceName(deviceId, reported);
    return (name == null || name.isEmpty) ? 'Unknown Device' : name;
  }

  /// A device renamed itself through the Connect hub: persist the new name
  /// and refresh presence + session records so every surface agrees.
  void _handleDeviceRenamed(String userId, String deviceId, String name) {
    if (_deviceNameStore.isInitialized) {
      unawaited(_deviceNameStore.setName(deviceId, name));
    }
    _connectionManager.renameDevice(deviceId, name);
    unawaited(_authService.renameDeviceSessions(deviceId, name));
  }

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

  /// Refuse WebSocket upgrades from an IP that is already holding the
  /// maximum number of not-yet-identified sockets.
  Response? _rejectWebSocketUpgradeIfFlooded(String remoteIp) {
    final pending = _pendingWebSocketCountByIp[remoteIp] ?? 0;
    if (pending < AriamiHttpServer._maxPendingWebSocketsPerIp) {
      return null;
    }
    return _jsonResponse(HttpStatus.tooManyRequests, {
      'error': {
        'code': 'TOO_MANY_PENDING_CONNECTIONS',
        'message': 'Too many unidentified WebSocket connections from this '
            'address; identify or close existing ones first',
      },
    });
  }

  /// Track a socket that has not identified yet: count it against its IP and
  /// close it if no identify arrives in time.
  void _trackPendingWebSocket(WebSocketChannel webSocket, String remoteIp) {
    _pendingWebSocketCountByIp[remoteIp] =
        (_pendingWebSocketCountByIp[remoteIp] ?? 0) + 1;
    _pendingWebSockets[webSocket] = _PendingWebSocketState(
      remoteIp: remoteIp,
      timeout: Timer(AriamiHttpServer._webSocketIdentifyTimeout, () {
        if (_pendingWebSockets.containsKey(webSocket)) {
          print('WebSocket closed: no identify within '
              '${AriamiHttpServer._webSocketIdentifyTimeout.inSeconds}s');
          try {
            webSocket.sink.close(4008, 'Identify timeout');
          } catch (_) {
            // Socket already torn down; onDone cleanup handles the rest.
          }
        }
      }),
    );
  }

  /// The socket identified (or closed): stop the identify timer and release
  /// its slot in the per-IP pending count.
  void _resolvePendingWebSocket(WebSocketChannel webSocket) {
    final pending = _pendingWebSockets.remove(webSocket);
    if (pending == null) {
      return;
    }
    pending.timeout.cancel();
    final count = _pendingWebSocketCountByIp[pending.remoteIp] ?? 0;
    if (count <= 1) {
      _pendingWebSocketCountByIp.remove(pending.remoteIp);
    } else {
      _pendingWebSocketCountByIp[pending.remoteIp] = count - 1;
    }
  }

  /// Handle WebSocket connection
  void _handleWebSocket(
    WebSocketChannel webSocket,
    String? subprotocol, {
    String remoteIp = 'unknown_ip',
  }) {
    print(
        'WebSocket client connected; waiting for identify (${_webSocketClients.length} active)');
    _trackPendingWebSocket(webSocket, remoteIp);

    final messages = webSocket.stream.asyncMap(
      (message) => _handleWebSocketMessage(webSocket, message),
    );
    messages.listen(
      (_) {},
      onDone: () {
        _resolvePendingWebSocket(webSocket);
        _webSocketClients.remove(webSocket);
        _webSocketSessionTokens.remove(webSocket);
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
        _resolvePendingWebSocket(webSocket);
        _webSocketClients.remove(webSocket);
        _webSocketSessionTokens.remove(webSocket);
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
  Future<void> _handleWebSocketMessage(
    WebSocketChannel webSocket,
    dynamic rawMessage,
  ) async {
    if (rawMessage is! String) {
      _sendWebSocketMessage(
        webSocket,
        WsMessage(
          type: AriamiConnectMessageType.error,
          data: const <String, dynamic>{
            'code': 'INVALID_MESSAGE',
            'message': 'Connect messages must be UTF-8 JSON text.',
          },
        ),
      );
      return;
    }
    // The maximum supported 5,000-track corpus is 7.63 MB. Reject above the
    // measured 8 MiB ceiling before JSON decoding allocates a second graph.
    if (!isConnectRawMessageWithinLimit(rawMessage)) {
      _sendWebSocketMessage(
        webSocket,
        WsMessage(
          type: AriamiConnectMessageType.error,
          data: const <String, dynamic>{
            'code': 'MESSAGE_TOO_LARGE',
            'message': 'That Connect message is too large.',
          },
        ),
      );
      return;
    }
    try {
      final jsonMessage = jsonDecode(rawMessage) as Map<String, dynamic>;
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

          final session = await _authService.validateSession(sessionToken);
          if (session == null) {
            // Close WebSocket with code 4001 (invalid session)
            webSocket.sink.close(4001, 'Session expired or invalid');
            return;
          }

          // Session valid - register or refresh client (upgrade clientType)
          if (deviceId.isNotEmpty) {
            _resolvePendingWebSocket(webSocket);
            _trackWebSocketClient(webSocket);
            _webSocketSessionTokens[webSocket] = sessionToken;
            _webSocketDeviceIds[webSocket] = deviceId;
            final effectiveType = _effectivePresenceClientType(
              deviceId: deviceId,
              deviceName: deviceName,
              wsClientType: clientType,
            );
            final effectiveName = _effectiveDeviceName(deviceId, deviceName);
            _connectionManager.registerOrRefreshClient(
              deviceId,
              effectiveName,
              userId: session.userId,
              clientType: effectiveType,
            );
            if (const {'desktop', 'mobile', 'tv'}.contains(clientType)) {
              _connectHub.register(
                webSocket,
                userId: session.userId,
                deviceId: deviceId,
                deviceName: effectiveName,
                clientType: clientType!,
              );
            }
          }
          return;
        }

        // First-run bootstrap mode - no auth required.
        if (deviceId.isNotEmpty) {
          _resolvePendingWebSocket(webSocket);
          _trackWebSocketClient(webSocket);
          _webSocketSessionTokens.remove(webSocket);
          _webSocketDeviceIds[webSocket] = deviceId;
          final effectiveType = _effectivePresenceClientType(
            deviceId: deviceId,
            deviceName: deviceName,
            wsClientType: clientType,
          );
          final effectiveName = _effectiveDeviceName(deviceId, deviceName);
          _connectionManager.registerOrRefreshClient(
            deviceId,
            effectiveName,
            clientType: effectiveType,
          );
          if (const {'desktop', 'mobile', 'tv'}.contains(clientType)) {
            _connectHub.register(
              webSocket,
              userId: 'legacy',
              deviceId: deviceId,
              deviceName: effectiveName,
              clientType: clientType!,
            );
          }
        }
        return;
      }

      // Handle ping
      if (message.type == WsMessageType.ping) {
        if (!await _revalidateWebSocketSession(webSocket)) return;
        final deviceId = _webSocketDeviceIds[webSocket];
        if (deviceId != null && deviceId.isNotEmpty) {
          _connectionManager.refreshHeartbeatIfRegistered(deviceId);
        }
        // Ping never reaches _connectHub.handle (we return here), but a
        // Connect peer that only pings is still alive and castable — tell
        // the hub's stale-peer sweep so it doesn't wrongly evict it.
        // Unconditional: touch() is a no-op for sockets the hub doesn't know.
        _connectHub.touch(webSocket);
        _sendWebSocketMessage(webSocket, PongMessage());
        return;
      }

      if (_connectHub.handle(webSocket, message)) {
        return;
      }

      // Other message types can be handled here in future phases
    } catch (e) {
      print('Error parsing WebSocket message: $e');
      _sendWebSocketMessage(
        webSocket,
        WsMessage(
          type: AriamiConnectMessageType.error,
          data: const <String, dynamic>{
            'code': 'INVALID_MESSAGE',
            'message': 'That Connect message is malformed.',
          },
        ),
      );
    }
  }

  /// Keeps an identified WebSocket's long-lived authority aligned with the
  /// session store. Successful validation refreshes the normal sliding TTL;
  /// revoked or expired sessions lose their current hub/presence access before
  /// close 4001 is sent.
  Future<bool> _revalidateWebSocketSession(
    WebSocketChannel webSocket,
  ) async {
    final sessionToken = _webSocketSessionTokens[webSocket];
    if (sessionToken == null) {
      if (!_hasRegisteredUsers()) return true;
      _closeWebSocketForAuthentication(webSocket);
      return false;
    }
    try {
      final session = await _authService.validateSession(sessionToken);
      if (_webSocketSessionTokens[webSocket] != sessionToken) return false;
      if (session != null) return true;
    } catch (_) {
      // A transient persistence failure must not sign out a valid user. The
      // next ping or maintenance pass will try again.
      return true;
    }
    _closeWebSocketForAuthentication(webSocket);
    return false;
  }

  void _closeWebSocketForAuthentication(WebSocketChannel webSocket) {
    _webSocketSessionTokens.remove(webSocket);
    _webSocketClients.remove(webSocket);
    _connectHub.unregister(webSocket);
    _untrackWebSocketDevice(webSocket);
    try {
      webSocket.sink.close(4001, 'Session expired or revoked');
    } catch (_) {
      // Socket teardown raced the revalidation result.
    }
  }

  Future<void> _revalidateWebSocketSessions() async {
    for (final webSocket in List<WebSocketChannel>.of(_webSocketClients)) {
      await _revalidateWebSocketSession(webSocket);
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
    Future.delayed(const Duration(seconds: 30), () async {
      if (_server != null) {
        await _cleanupStaleConnectionsWithBroadcast();
        if (_server != null) _startCleanupTimer();
      }
    });
  }

  /// Cleanup stale connections and broadcast to WebSocket clients if any were removed
  Future<void> _cleanupStaleConnectionsWithBroadcast() async {
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
    await _revalidateWebSocketSessions();
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
