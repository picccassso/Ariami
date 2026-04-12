part of '../http_server.dart';

extension AriamiHttpServerSetupAndStatsHandlersMethods on AriamiHttpServer {
  Response _setupNotConfiguredResponse({
    String message = 'Setup not configured',
  }) {
    return _jsonOk({'success': false, 'message': message});
  }

  Response _setupCallbackErrorResponse(String action, Object error) {
    return _jsonInternalServerError({
      'error': 'Failed to $action',
      'message': error.toString(),
    });
  }

  /// Handle ping request
  /// Optionally accepts deviceId query parameter to update heartbeat
  Response _handlePing(Request request) {
    // Update heartbeat if deviceId is provided
    final deviceId = request.url.queryParameters['deviceId'];
    if (deviceId != null && deviceId.isNotEmpty) {
      _connectionManager.refreshHeartbeatIfRegistered(deviceId);
    }

    return _jsonOk({
      'status': 'ok',
      'timestamp': DateTime.now().toIso8601String(),
      'server': Platform.localHostname,
      'version': '4.1.0',
    });
  }

  /// Handle Tailscale status request
  Future<Response> _handleTailscaleStatus(Request request) async {
    if (_tailscaleStatusCallback != null) {
      try {
        final status = await _tailscaleStatusCallback!();
        return _jsonOk(status);
      } catch (e) {
        return _setupCallbackErrorResponse('get Tailscale status', e);
      }
    }

    // Tailscale not configured (e.g., desktop app)
    return _jsonOk({
      'isInstalled': false,
      'isRunning': false,
      'ip': null,
    });
  }

  /// Handle set music folder request
  Future<Response> _handleSetMusicFolder(Request request) async {
    if (_setMusicFolderCallback == null) {
      return _setupNotConfiguredResponse();
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final path = data['path'] as String?;

      if (path == null || path.isEmpty) {
        return _jsonBadRequest({
          'error': 'Missing required field',
          'message': 'path is required',
        });
      }

      final success = await _setMusicFolderCallback!(path);
      return _jsonOk({'success': success});
    } catch (e) {
      return _setupCallbackErrorResponse('set music folder', e);
    }
  }

  /// Handle start scan request
  Future<Response> _handleStartScan(Request request) async {
    if (_startScanCallback == null) {
      return _setupNotConfiguredResponse();
    }

    try {
      final success = await _startScanCallback!();
      return _jsonOk({
        'success': success,
        'message': success ? 'Scan started' : 'Failed to start scan',
      });
    } catch (e) {
      return _setupCallbackErrorResponse('start scan', e);
    }
  }

  /// Handle get scan status request
  Future<Response> _handleGetScanStatus(Request request) async {
    if (_getScanStatusCallback != null) {
      try {
        final status = await _getScanStatusCallback!();
        return _jsonOk(status);
      } catch (e) {
        return _setupCallbackErrorResponse('get scan status', e);
      }
    }

    // Return default status if not configured
    return _jsonOk({
      'isScanning': false,
      'progress': 0.0,
      'songsFound': 0,
      'albumsFound': 0,
      'currentStatus': 'Not configured',
    });
  }

  /// Handle mark setup complete request
  Future<Response> _handleMarkSetupComplete(Request request) async {
    if (_markSetupCompleteCallback == null) {
      return _setupNotConfiguredResponse();
    }

    try {
      final success = await _markSetupCompleteCallback!();
      return _jsonOk({'success': success});
    } catch (e) {
      return _setupCallbackErrorResponse('mark setup complete', e);
    }
  }

  /// Handle get setup status request (check if setup is complete)
  Future<Response> _handleGetSetupStatus(Request request) async {
    if (_getSetupStatusCallback != null) {
      try {
        final isComplete = await _getSetupStatusCallback!();
        return _jsonOk({'isComplete': isComplete});
      } catch (e) {
        return _setupCallbackErrorResponse('get setup status', e);
      }
    }

    // If no callback configured, assume setup is not complete
    return _jsonOk({'isComplete': false});
  }

  /// Handle transition to background mode request (CLI use)
  Future<Response> _handleTransitionToBackground(Request request) async {
    if (_transitionToBackgroundCallback == null) {
      return _setupNotConfiguredResponse(message: 'Transition not configured');
    }

    try {
      final result = await _transitionToBackgroundCallback!();
      return _jsonOk(result);
    } catch (e) {
      return _setupCallbackErrorResponse('transition to background', e);
    }
  }

  /// Handle get stats request (for dashboard)
  Response _handleGetStats(Request request) {
    final library = _libraryManager.library;
    final isScanning = _libraryManager.isScanning;
    final lastScanTime = _libraryManager.lastScanTime;
    final connectedClients = _connectionManager.clientCount;
    final mobileClients = _connectionManager.mobileClientCount;

    return _jsonOk(
      {
        'songCount': library?.totalSongs ?? 0,
        'albumCount': library?.totalAlbums ?? 0,
        'connectedClients': connectedClients,
        'mobileClients': mobileClients,
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
      },
      headers: {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
      },
    );
  }

  /// Handle get server info request (for QR code generation)
  Response _handleGetServerInfo(Request request) {
    final serverInfo = getServerInfo();
    return _jsonOk(serverInfo);
  }
}
