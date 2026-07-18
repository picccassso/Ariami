part of '../http_server.dart';

extension AriamiHttpServerAdminHandlersMethods on AriamiHttpServer {
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

  Response _handleAdminRegistrationToken(Request request) {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    return _jsonOk(_createRegistrationTokenPayload());
  }

  /// Admin-only: mint a short, typeable invite code for manual-entry signup.
  Response _handleAdminInviteCode(Request request) {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    return _jsonOk(_createInviteCodePayload());
  }

  /// Admin-only: read the sign-in account-picker setting.
  Response _handleAdminGetUserPicker(Request request) {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    return _jsonOk({'enabled': _publicUserPickerEnabled});
  }

  /// Admin-only: enable/disable the sign-in account picker at runtime.
  ///
  /// Flips the in-memory setting only; the hosting app persists the owner's
  /// choice and re-applies it on startup.
  Future<Response> _handleAdminSetUserPicker(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    try {
      final body = await request.readAsString();
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;

      final enabled = data['enabled'];
      if (enabled is! bool) {
        return _jsonBadRequest({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'enabled (boolean) is required',
          },
        });
      }

      setPublicUserPickerEnabled(enabled);

      // The runtime change is applied either way; a persist failure is
      // surfaced so the admin knows the choice may not survive a restart.
      final persist = _publicUserPickerPersistCallback;
      if (persist != null) {
        try {
          await persist(enabled);
        } catch (e) {
          return _jsonInternalServerError({
            'error': {
              'code': 'PERSIST_FAILED',
              'message': 'Setting applied, but saving it for future '
                  'restarts failed: $e',
            },
          });
        }
      }

      return _jsonOk({'enabled': _publicUserPickerEnabled});
    } catch (_) {
      return _jsonBadRequest({
        'error': {
          'code': 'INVALID_REQUEST',
          'message': 'Invalid request body',
        },
      });
    }
  }

  Response _handleAdminUsers(Request request) {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    final connectedDeviceCountByUserId = <String, int>{};
    for (final client in _connectionManager.getConnectedClients()) {
      final userId = client.userId;
      if (userId == null ||
          userId.isEmpty ||
          _isDashboardControlClient(
            deviceId: client.deviceId,
            deviceName: client.deviceName,
          )) {
        continue;
      }
      connectedDeviceCountByUserId[userId] =
          (connectedDeviceCountByUserId[userId] ?? 0) + 1;
    }

    final rows = _authService.getUsers().map((user) {
      return {
        'userId': user.userId,
        'username': user.username,
        'createdAt': user.createdAt,
        'isAdmin': _authService.isAdminUser(user.userId),
        'connectedDeviceCount': connectedDeviceCountByUserId[user.userId] ?? 0,
      };
    }).toList(growable: false);

    return _jsonOk({'users': rows});
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

  Response _handleAdminUserActivity(Request request) {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    final rows = getActiveUserActivityRows();
    return Response.ok(
      jsonEncode({
        'users': rows.map((row) => row.toJson()).toList(growable: false),
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _handleAdminGetTranscodeSlots(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    final callback = _getTranscodeSlotsSnapshotCallback;
    if (callback == null) {
      return _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'NOT_CONFIGURED',
          'message': 'Transcode slot configuration is not available',
        },
      });
    }

    try {
      final snapshot = await callback();
      return _jsonOk(snapshot.toJson());
    } catch (e) {
      return _jsonBadRequest({
        'error': {
          'code': 'INVALID_REQUEST',
          'message': e.toString(),
        },
      });
    }
  }

  Future<Response> _handleAdminPostTranscodeSlots(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    final callback = _setTranscodeSlotsOverrideCallback;
    if (callback == null) {
      return _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'NOT_CONFIGURED',
          'message': 'Transcode slot configuration is not available',
        },
      });
    }

    try {
      final body = await request.readAsString();
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;

      if (data['reset'] == true) {
        final snapshot = await callback(null);
        return _jsonOk(snapshot.toJson());
      }

      final slotsValue = data['slots'];
      if (slotsValue == null) {
        return _jsonBadRequest({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'slots is required unless reset is true',
          },
        });
      }

      if (slotsValue is! num || slotsValue != slotsValue.roundToDouble()) {
        return _jsonBadRequest({
          'error': {
            'code': 'INVALID_REQUEST',
            'message':
                'slots must be an integer >= ${TranscodeSlotsPolicy.minSlots}',
          },
        });
      }

      final slots = slotsValue.toInt();
      TranscodeSlotsPolicy.validateSlots(slots);
      final snapshot = await callback(slots);
      return _jsonOk(snapshot.toJson());
    } on ArgumentError catch (e) {
      return _jsonBadRequest({
        'error': {
          'code': 'INVALID_REQUEST',
          'message': e.message?.toString() ?? e.toString(),
        },
      });
    } catch (e) {
      return _jsonInternalServerError({
        'error': {
          'code': 'INTERNAL_ERROR',
          'message': e.toString(),
        },
      });
    }
  }

  Future<Response> _handleAdminCreateUser(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    try {
      final body = await request.readAsString();
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;

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
      updateAuthMode();

      return _jsonResponse(HttpStatus.created, {
        'status': 'user_created',
        'userId': response.userId,
        'username': response.username,
      });
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
    } catch (_) {
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

  void _revokeStreamTicketsAndDisconnectDevices(List<Session> revokedSessions) {
    for (final session in revokedSessions) {
      _streamTracker.revokeSessionTickets(session.sessionToken);
    }

    final deviceIds = revokedSessions.map((s) => s.deviceId).toSet();
    for (final deviceId in deviceIds) {
      final closedWebSockets = _closeWebSocketsForDevice(deviceId);
      final removedClient = _connectionManager.unregisterClientAndGet(deviceId);
      if (removedClient != null || closedWebSockets > 0) {
        broadcastWebSocketMessage(ClientDisconnectedMessage(
          clientCount: _connectionManager.clientCount,
          deviceName: removedClient?.deviceName,
        ));
      }
    }
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
      _revokeStreamTicketsAndDisconnectDevices(revokedSessions);

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

  Future<Response> _handleAdminDeleteUser(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    try {
      final body = await request.readAsString();
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;

      final requestedUserId = data['userId'] as String?;
      final requestedUsername = data['username'] as String?;
      if ((requestedUserId == null || requestedUserId.trim().isEmpty) &&
          (requestedUsername == null || requestedUsername.trim().isEmpty)) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'userId or username is required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      User? targetUser;
      if (requestedUserId != null && requestedUserId.trim().isNotEmpty) {
        targetUser = _authService.getUserById(requestedUserId.trim());
      }
      targetUser ??= requestedUsername == null
          ? null
          : _authService.getUserByUsername(requestedUsername.trim());

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
      final targetUserId = targetUser.userId;
      final isDeletingOnlyAdmin =
          _authService.isAdminUser(targetUserId) && _authService.userCount <= 1;
      if (isDeletingOnlyAdmin) {
        return Response(
          409,
          body: jsonEncode({
            'error': {
              'code': AuthErrorCodes.lastAdminProtected,
              'message': 'Cannot delete the last remaining admin account',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final revokedSessions =
          await _authService.revokeAllSessionsForUserWithDetails(
        targetUserId,
      );
      _revokeStreamTicketsAndDisconnectDevices(revokedSessions);

      // Defensive cleanup for any stale connected rows that might not map to a
      // currently active session.
      final staleConnectedDeviceIds = _connectionManager
          .getConnectedClients()
          .where((client) => client.userId == targetUserId)
          .map((client) => client.deviceId)
          .toSet();
      for (final deviceId in staleConnectedDeviceIds) {
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

      final deletedUser = await _authService.deleteUserById(targetUserId);
      if (deletedUser == null) {
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

      updateAuthMode();

      return Response.ok(
        jsonEncode({
          'status': 'user_deleted',
          'userId': deletedUser.userId,
          'username': deletedUser.username,
          'revokedSessionCount': revokedSessions.length,
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (_) {
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
}
