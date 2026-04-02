part of '../http_server.dart';

extension AriamiHttpServerAuthAndAdminHandlersMethods on AriamiHttpServer {
  /// Handle user registration
  Future<Response> _handleAuthRegister(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final username = data['username'] as String?;
      final password = data['password'] as String?;

      if (username == null || password == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'username and password are required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final response = await _authService.register(username, password);

      // Update auth mode after first user registration
      if (_authService.userCount == 1) {
        updateAuthMode();
      }

      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on UserExistsException {
      return Response(
        409,
        body: jsonEncode({
          'error': {
            'code': AuthErrorCodes.userExists,
            'message': 'Username already taken',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on AuthException catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': {
            'code': e.code,
            'message': e.message,
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle user login
  Future<Response> _handleAuthLogin(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final username = data['username'] as String?;
      final password = data['password'] as String?;
      final deviceId = data['deviceId'] as String?;
      final deviceName = data['deviceName'] as String?;

      if (username == null ||
          password == null ||
          deviceId == null ||
          deviceName == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message':
                  'username, password, deviceId, and deviceName are required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final response =
          await _authService.login(username, password, deviceId, deviceName);

      // Register client connection
      _connectionManager.registerClient(
        deviceId,
        deviceName,
        userId: response.userId,
      );

      // Broadcast client connection
      broadcastWebSocketMessage(ClientConnectedMessage(
        clientCount: _connectionManager.clientCount,
        deviceName: deviceName,
      ));

      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on AuthException catch (e) {
      return Response.unauthorized(
        jsonEncode({
          'error': {
            'code': e.code,
            'message': e.message,
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle user logout
  Future<Response> _handleAuthLogout(Request request) async {
    // Session is attached by auth middleware
    final session = request.context['session'] as Session?;
    if (session == null) {
      return Response.unauthorized(
        jsonEncode({
          'error': {
            'code': AuthErrorCodes.authRequired,
            'message': 'Not authenticated',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    // Revoke session
    final response = await _authService.logout(session.sessionToken);

    // Revoke any stream tickets for this session
    _streamTracker.revokeSessionTickets(session.sessionToken);

    // Unregister client connection
    final client = _connectionManager.getClient(session.deviceId);
    _connectionManager.unregisterClient(session.deviceId);

    // Broadcast client disconnection
    broadcastWebSocketMessage(ClientDisconnectedMessage(
      clientCount: _connectionManager.clientCount,
      deviceName: client?.deviceName,
    ));

    return Response.ok(
      jsonEncode(response.toJson()),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  /// Handle get current user info
  Response _handleGetMe(Request request) {
    final session = request.context['session'] as Session?;
    if (session == null) {
      return Response.unauthorized(
        jsonEncode({
          'error': {
            'code': AuthErrorCodes.authRequired,
            'message': 'Not authenticated',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final user = _authService.getUserById(session.userId);
    if (user == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'USER_NOT_FOUND',
            'message': 'User not found',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    return Response.ok(
      jsonEncode({
        'userId': user.userId,
        'username': user.username,
        'deviceId': session.deviceId,
        'deviceName': session.deviceName,
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Response? _authorizeAdminRequest(Request request) {
    final session = request.context['session'] as Session?;
    if (session == null) {
      return _authRequiredResponse();
    }
    if (!_authService.isAdminUser(session.userId)) {
      return _forbiddenAdminResponse();
    }
    return null;
  }

  Future<Response> _handleAdminConnectedClients(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    final clients = _connectionManager.getConnectedClients();
    final rows = clients.map((client) {
      final userId = client.userId;
      final username =
          userId == null ? null : _authService.getUserById(userId)?.username;
      return {
        'deviceId': client.deviceId,
        'deviceName': client.deviceName,
        'clientType': _resolveConnectedClientType(client),
        'userId': userId,
        'username': username,
        'connectedAt': client.connectedAt.toUtc().toIso8601String(),
        'lastHeartbeat': client.lastHeartbeat.toUtc().toIso8601String(),
      };
    }).toList();

    return Response.ok(
      jsonEncode({'clients': rows}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  String _resolveConnectedClientType(ConnectedClient client) {
    if (_isDashboardControlClient(
      deviceId: client.deviceId,
      deviceName: client.deviceName,
    )) {
      return AriamiHttpServer._clientTypeDashboard;
    }
    if (client.userId == null) {
      return AriamiHttpServer._clientTypeUnauthenticated;
    }
    return AriamiHttpServer._clientTypeUserDevice;
  }

  bool _isDashboardControlClient({
    required String deviceId,
    required String deviceName,
  }) {
    if (deviceId == AriamiHttpServer._desktopDashboardAdminDeviceId) {
      return true;
    }
    return deviceName == AriamiHttpServer._desktopDashboardAdminDeviceName ||
        deviceName == AriamiHttpServer._cliWebDashboardDeviceName;
  }

  int _closeWebSocketsForDevice(String deviceId) {
    final socketsToClose = _webSocketDeviceIds.entries
        .where((entry) => entry.value == deviceId)
        .map((entry) => entry.key)
        .toList(growable: false);

    var closedCount = 0;
    for (final socket in socketsToClose) {
      _webSocketDeviceIds.remove(socket);
      _webSocketClients.remove(socket);
      try {
        socket.sink.close(4002, 'Disconnected by admin');
        closedCount++;
      } catch (e) {
        print('Error closing WebSocket for $deviceId: $e');
      }
    }

    return closedCount;
  }

  Future<Response> _handleAdminKickClient(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    try {
      final body = await request.readAsString();
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;

      final deviceId = data['deviceId'] as String?;
      if (deviceId == null || deviceId.trim().isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'deviceId is required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final normalizedDeviceId = deviceId.trim();
      final existingClient = _connectionManager.getClient(normalizedDeviceId);
      final existingSessions =
          _authService.getSessionsForDevice(normalizedDeviceId);
      if (existingClient == null && existingSessions.isEmpty) {
        return Response.notFound(
          jsonEncode({
            'error': {
              'code': 'CLIENT_NOT_FOUND',
              'message': 'No connected client found for deviceId',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final revokedSessions =
          await _authService.revokeSessionsForDevice(normalizedDeviceId);
      for (final session in revokedSessions) {
        _streamTracker.revokeSessionTickets(session.sessionToken);
      }

      final closedWebSockets = _closeWebSocketsForDevice(normalizedDeviceId);
      final removedClient =
          _connectionManager.unregisterClientAndGet(normalizedDeviceId);

      if (removedClient != null || closedWebSockets > 0) {
        broadcastWebSocketMessage(ClientDisconnectedMessage(
          clientCount: _connectionManager.clientCount,
          deviceName: removedClient?.deviceName ?? existingClient?.deviceName,
        ));
      }

      return Response.ok(
        jsonEncode({
          'status': 'kicked',
          'deviceId': normalizedDeviceId,
          'revokedSessionCount': revokedSessions.length,
          'closedWebSocketCount': closedWebSockets,
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'Invalid request body',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  Future<Response> _handleAdminChangePassword(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    try {
      final body = await request.readAsString();
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;

      final username = data['username'] as String?;
      final newPassword = data['newPassword'] as String?;
      if (username == null || newPassword == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'username and newPassword are required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final targetUser = _authService.getUserByUsername(username.trim());
      if (targetUser == null) {
        return Response.notFound(
          jsonEncode({
            'error': {
              'code': 'USER_NOT_FOUND',
              'message': 'User not found',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      await _authService.changePassword(targetUser.username, newPassword);
      final revokedSessions =
          await _authService.revokeAllSessionsForUserWithDetails(
        targetUser.userId,
      );

      for (final session in revokedSessions) {
        _streamTracker.revokeSessionTickets(session.sessionToken);
      }

      final deviceIds = revokedSessions.map((s) => s.deviceId).toSet();
      for (final deviceId in deviceIds) {
        final closedWebSockets = _closeWebSocketsForDevice(deviceId);
        final removedClient =
            _connectionManager.unregisterClientAndGet(deviceId);
        if (removedClient != null || closedWebSockets > 0) {
          broadcastWebSocketMessage(ClientDisconnectedMessage(
            clientCount: _connectionManager.clientCount,
            deviceName: removedClient?.deviceName,
          ));
        }
      }

      return Response.ok(
        jsonEncode({
          'status': 'password_changed',
          'username': targetUser.username,
          'revokedSessionCount': revokedSessions.length,
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on AuthException catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': {
            'code': e.code,
            'message': e.message,
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'Invalid request body',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle stream ticket request (for authenticated streaming)
  Future<Response> _handleStreamTicket(Request request) async {
    // Session is attached by auth middleware
    final session = request.context['session'] as Session?;
    if (session == null) {
      return Response.unauthorized(
        jsonEncode({
          'error': {
            'code': AuthErrorCodes.authRequired,
            'message': 'Not authenticated',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final songId = data['songId'] as String?;
      final quality = data['quality'] as String?;

      if (songId == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'songId is required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // Get song duration from LibraryManager
      final durationSeconds =
          await _libraryManager.getSongDuration(songId) ?? 0;

      // Issue stream ticket
      final ticket = _streamTracker.issueTicket(
        userId: session.userId,
        sessionToken: session.sessionToken,
        songId: songId,
        durationSeconds: durationSeconds,
        quality: quality,
      );

      return Response.ok(
        jsonEncode(StreamTicketResponse(
          streamToken: ticket.token,
          expiresAt: ticket.expiresAt.toIso8601String(),
        ).toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'error': {
            'code': 'INTERNAL_ERROR',
            'message': 'Failed to issue stream ticket',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }
}
