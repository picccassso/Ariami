part of '../http_server.dart';

extension AriamiHttpServerSetupAndStatsHandlersMethods on AriamiHttpServer {
  /// Handle ping request
  /// Optionally accepts deviceId query parameter to update heartbeat
  Response _handlePing(Request request) {
    // Update heartbeat if deviceId is provided
    final deviceId = request.url.queryParameters['deviceId'];
    if (deviceId != null && deviceId.isNotEmpty) {
      _connectionManager.refreshHeartbeatIfRegistered(deviceId);
    }

    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'timestamp': DateTime.now().toIso8601String(),
        'server': Platform.localHostname,
        'version': '3.2.0',
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  /// Handle Tailscale status request
  Future<Response> _handleTailscaleStatus(Request request) async {
    if (_tailscaleStatusCallback != null) {
      try {
        final status = await _tailscaleStatusCallback!();
        return Response.ok(
          jsonEncode(status),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to get Tailscale status',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    } else {
      // Tailscale not configured (e.g., desktop app)
      return Response.ok(
        jsonEncode({
          'isInstalled': false,
          'isRunning': false,
          'ip': null,
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle set music folder request
  Future<Response> _handleSetMusicFolder(Request request) async {
    if (_setMusicFolderCallback != null) {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final path = data['path'] as String?;

        if (path == null || path.isEmpty) {
          return Response.badRequest(
            body: jsonEncode({
              'error': 'Missing required field',
              'message': 'path is required',
            }),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
          );
        }

        final success = await _setMusicFolderCallback!(path);
        return Response.ok(
          jsonEncode({'success': success}),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to set music folder',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    } else {
      return Response.ok(
        jsonEncode({'success': false, 'message': 'Setup not configured'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle start scan request
  Future<Response> _handleStartScan(Request request) async {
    if (_startScanCallback != null) {
      try {
        final success = await _startScanCallback!();
        return Response.ok(
          jsonEncode({
            'success': success,
            'message': success ? 'Scan started' : 'Failed to start scan',
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to start scan',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    } else {
      return Response.ok(
        jsonEncode({'success': false, 'message': 'Setup not configured'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle get scan status request
  Future<Response> _handleGetScanStatus(Request request) async {
    if (_getScanStatusCallback != null) {
      try {
        final status = await _getScanStatusCallback!();
        return Response.ok(
          jsonEncode(status),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to get scan status',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    } else {
      // Return default status if not configured
      return Response.ok(
        jsonEncode({
          'isScanning': false,
          'progress': 0.0,
          'songsFound': 0,
          'albumsFound': 0,
          'currentStatus': 'Not configured',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle mark setup complete request
  Future<Response> _handleMarkSetupComplete(Request request) async {
    if (_markSetupCompleteCallback != null) {
      try {
        final success = await _markSetupCompleteCallback!();
        return Response.ok(
          jsonEncode({'success': success}),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to mark setup complete',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    } else {
      return Response.ok(
        jsonEncode({'success': false, 'message': 'Setup not configured'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle get setup status request (check if setup is complete)
  Future<Response> _handleGetSetupStatus(Request request) async {
    if (_getSetupStatusCallback != null) {
      try {
        final isComplete = await _getSetupStatusCallback!();
        return Response.ok(
          jsonEncode({'isComplete': isComplete}),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to get setup status',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    } else {
      // If no callback configured, assume setup is not complete
      return Response.ok(
        jsonEncode({'isComplete': false}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle transition to background mode request (CLI use)
  Future<Response> _handleTransitionToBackground(Request request) async {
    if (_transitionToBackgroundCallback != null) {
      try {
        final result = await _transitionToBackgroundCallback!();
        return Response.ok(
          jsonEncode(result),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to transition to background',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    } else {
      return Response.ok(
        jsonEncode({'success': false, 'message': 'Transition not configured'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle get stats request (for dashboard)
  Response _handleGetStats(Request request) {
    final library = _libraryManager.library;
    final isScanning = _libraryManager.isScanning;
    final lastScanTime = _libraryManager.lastScanTime;
    final connectedClients = _connectionManager.clientCount;

    return Response.ok(
      jsonEncode({
        'songCount': library?.totalSongs ?? 0,
        'albumCount': library?.totalAlbums ?? 0,
        'connectedClients': connectedClients,
        'isScanning': isScanning,
        'lastScanTime': lastScanTime?.toIso8601String(),
        'serverRunning': true,
        // Multi-user auth stats
        'connectedUsers': _connectionManager.uniqueUserCount,
        'connectedDevices': connectedClients,
        'activeSessions': _authService.sessionCount,
        'registeredUsers': _authService.userCount,
        'authRequired': _authRequired,
        'legacyMode': _legacyMode,
      }),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
      },
    );
  }

  /// Handle get server info request (for QR code generation)
  Response _handleGetServerInfo(Request request) {
    final serverInfo = getServerInfo();
    return Response.ok(
      jsonEncode(serverInfo),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
}
