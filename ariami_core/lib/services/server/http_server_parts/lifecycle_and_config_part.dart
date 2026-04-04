part of '../http_server.dart';

extension AriamiHttpServerLifecycleMethods on AriamiHttpServer {
  /// Check if server is running
  bool get isRunning => _server != null;

  /// Set the path where web assets are located (for serving web UI)
  void setWebAssetsPath(String path) {
    _webAssetsPath = path;
  }

  /// Set the transcoding service for quality-based streaming.
  ///
  /// Must be called before streaming at non-high quality levels.
  /// The transcoding service handles FFmpeg-based transcoding and caching.
  void setTranscodingService(TranscodingService service) {
    _transcodingService = service;
  }

  /// Get the transcoding service (if configured)
  TranscodingService? get transcodingService => _transcodingService;

  /// Set the artwork service for thumbnail generation.
  ///
  /// Must be called before requesting thumbnails.
  /// The artwork service handles FFmpeg-based resizing and caching.
  void setArtworkService(ArtworkService service) {
    _artworkService = service;
  }

  /// Get the artwork service (if configured)
  ArtworkService? get artworkService => _artworkService;

  /// Set callback for getting Tailscale status (optional, for CLI use)
  void setTailscaleStatusCallback(
      Future<Map<String, dynamic>> Function() callback) {
    _tailscaleStatusCallback = callback;
  }

  /// Set setup operation callbacks (optional, for CLI use)
  void setSetupCallbacks({
    Future<bool> Function(String)? setMusicFolder,
    Future<bool> Function()? startScan,
    Future<Map<String, dynamic>> Function()? getScanStatus,
    Future<bool> Function()? markSetupComplete,
    Future<bool> Function()? getSetupStatus,
  }) {
    _setMusicFolderCallback = setMusicFolder;
    _startScanCallback = startScan;
    _getScanStatusCallback = getScanStatus;
    _markSetupCompleteCallback = markSetupComplete;
    _getSetupStatusCallback = getSetupStatus;
  }

  /// Set callback for transitioning from foreground to background mode (CLI use)
  void setTransitionToBackgroundCallback(
      Future<Map<String, dynamic>> Function() callback) {
    _transitionToBackgroundCallback = callback;
  }

  /// Initialize auth services for multi-user support.
  /// Must be called before server start if auth is needed.
  ///
  /// Parameters:
  /// - [usersFilePath]: Path to the users JSON file
  /// - [sessionsFilePath]: Path to the sessions JSON file
  Future<void> initializeAuth({
    required String usersFilePath,
    required String sessionsFilePath,
    bool forceReinitialize = false,
  }) async {
    if (forceReinitialize) {
      _authService.resetForTesting();
    }

    // Initialize AuthService with storage paths
    await _authService.initialize(usersFilePath, sessionsFilePath);

    // Initialize StreamTracker (starts cleanup timer)
    _streamTracker.initialize();

    // Set initial auth mode based on whether users exist
    updateAuthMode();

    print(
        '[HttpServer] Auth services initialized - users: $usersFilePath, sessions: $sessionsFilePath');
  }

  /// Start the HTTP server
  ///
  /// Parameters:
  /// - [advertisedIp]: The IP to show in QR code (Tailscale or LAN IP)
  /// - [bindAddress]: The address to bind to (default: '0.0.0.0' for all interfaces)
  /// - [port]: The port to listen on (default: 8080)
  Future<void> start({
    required String advertisedIp,
    String? tailscaleIp,
    String? lanIp,
    String bindAddress = '0.0.0.0',
    int port = 8080,
  }) async {
    // If already running, don't start again
    if (_server != null) {
      // Update stored IP/port even if server is already running
      _advertisedIp = advertisedIp;
      _tailscaleIp = tailscaleIp;
      _lanIp = lanIp;
      _port = port;
      print('Ariami Server already running on http://$_advertisedIp:$_port');
      return;
    }
    _advertisedIp = advertisedIp;
    _tailscaleIp = tailscaleIp;
    _lanIp = lanIp;
    _port = port;

    _validateFeatureFlagInvariantsOrThrow();

    _registerLibraryListeners();

    final router = _buildRouter();

    // Build handler with Cascade to support both API and static files
    final Handler cascadeHandler = Cascade()
        .add(router.call) // API routes have priority
        .add(_webAssetsPath != null
            ? _createStaticHandler()
            : _notFoundHandler())
        .handler;

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_authMiddleware())
        .addMiddleware(_connectionTrackingMiddleware())
        .addMiddleware(_metricsMiddleware())
        .addMiddleware(_errorMiddleware())
        .addHandler(cascadeHandler);

    try {
      _server = await shelf_io.serve(
        handler,
        bindAddress,
        port,
      );
      print('Ariami Server started on http://$bindAddress:$port');
      print('Advertised IP for QR code: $advertisedIp');
      if (_webAssetsPath != null) {
        print('Serving web UI from: $_webAssetsPath');
      }
      _metricsService.start();

      // Start cleanup timer for stale connections
      _startCleanupTimer();
    } catch (e) {
      print('Failed to start server: $e');
      rethrow;
    }
  }

  void _registerLibraryListeners() {
    if (_libraryListenersRegistered) return;

    _scanCompleteListener = () {
      final reason = _libraryManager.isScanning ? 'scan_complete' : 'fs_change';
      _broadcastLibraryUpdated(syncReason: reason);
    };
    _durationsReadyListener = () {
      _broadcastLibraryUpdated(syncReason: 'durations_ready');
    };

    _libraryManager.addScanCompleteListener(_scanCompleteListener!);
    _libraryManager.addDurationsReadyListener(_durationsReadyListener!);
    _libraryListenersRegistered = true;
  }

  void _broadcastLibraryUpdated({String? syncReason}) {
    final library = _libraryManager.library;
    notifyLibraryUpdated(
      albumCount: library?.totalAlbums ?? 0,
      songCount: library?.totalSongs ?? 0,
    );

    if (syncReason != null) {
      notifySyncTokenAdvanced(
        latestToken: _libraryManager.latestToken,
        reason: syncReason,
      );
    }
  }

  /// Stop the HTTP server
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;

    // Clear all connected clients since server is stopping
    _connectionManager.clearAll();

    // Close all WebSocket connections
    for (final client in _webSocketClients) {
      try {
        await client.sink.close();
      } catch (e) {
        // Ignore errors when closing
      }
    }
    _webSocketClients.clear();
    _metricsService.stop();

    print('Ariami Server stopped');
  }

  /// Get server info for QR code generation
  Map<String, dynamic> getServerInfo() {
    return {
      'server': _advertisedIp ?? _tailscaleIp,
      'lanServer': _lanIp,
      'tailscaleServer': _tailscaleIp,
      'port': _port,
      'name': Platform.localHostname,
      'version': '3.2.0',
      'authRequired': _authRequired,
      'legacyMode': _legacyMode,
      'downloadLimits': {
        'maxConcurrent': _maxConcurrentDownloads,
        'maxQueue': _maxDownloadQueue,
        'maxConcurrentPerUser': _maxConcurrentDownloadsPerUser,
        'maxQueuePerUser': _maxDownloadQueuePerUser,
      },
    };
  }

  /// Configure download limits (call before server start)
  void setDownloadLimits({
    required int maxConcurrent,
    required int maxQueue,
    required int maxConcurrentPerUser,
    required int maxQueuePerUser,
  }) {
    _maxConcurrentDownloads = maxConcurrent;
    _maxDownloadQueue = maxQueue;
    _maxConcurrentDownloadsPerUser = maxConcurrentPerUser;
    _maxDownloadQueuePerUser = maxQueuePerUser;
    _downloadLimiter = _WeightedFairDownloadLimiter(
      maxConcurrent: _maxConcurrentDownloads,
      maxQueue: _maxDownloadQueue,
      maxConcurrentPerUser: _maxConcurrentDownloadsPerUser,
      maxQueuePerUser: _maxDownloadQueuePerUser,
    );
    print('[HttpServer] Download limits set: '
        'global=$maxConcurrent queue=$maxQueue '
        'perUser=$maxConcurrentPerUser perUserQueue=$maxQueuePerUser');
  }

  /// Set music folder path for security validation
  void setMusicFolderPath(String path) {
    _musicFolderPath = path;
  }

  /// Set auth flags for multi-user support
  void setAuthFlags({required bool authRequired, required bool legacyMode}) {
    _authRequired = authRequired;
    _legacyMode = legacyMode;
  }

  /// Set feature flags used for phased rollout.
  void setFeatureFlags(AriamiFeatureFlags flags) {
    if (flags.enableDownloadJobs && !flags.enableV2Api) {
      throw StateError(
        'Invalid feature flag configuration: enableDownloadJobs=true '
        'requires enableV2Api=true.',
      );
    }
    _featureFlags = flags;
    print('[HttpServer] Feature flags set: ${flags.toJson()}');
  }

  /// Get current feature flags.
  AriamiFeatureFlags get featureFlags => _featureFlags;

  void _validateFeatureFlagInvariantsOrThrow() {
    if (_featureFlags.enableDownloadJobs && !_featureFlags.enableV2Api) {
      throw StateError(
        'Invalid feature flag configuration: enableDownloadJobs=true '
        'requires enableV2Api=true.',
      );
    }

    if (_featureFlags.enableV2Api &&
        _libraryManager.createCatalogRepository() == null) {
      throw StateError(
        'Invalid startup configuration: enableV2Api=true requires catalog '
        'repository availability. Ensure LibraryManager.setCachePath(...) '
        'succeeds before starting the HTTP server.',
      );
    }
  }

  /// Update auth mode based on whether users exist.
  /// Call this at server startup (after AuthService initialized) and after first user registration.
  void updateAuthMode() {
    final hasUsers = _authService.hasUsers();
    _authRequired = hasUsers;
    _legacyMode = !hasUsers;
    print(
        '[HttpServer] Auth mode updated - authRequired: $_authRequired, legacyMode: $_legacyMode');
  }

  /// Get connection manager
  ConnectionManager get connectionManager => _connectionManager;

  /// Get library manager
  LibraryManager get libraryManager => _libraryManager;

  /// Get number of connected users (unique user accounts)
  int get connectedUsers => _connectionManager.uniqueUserCount;

  /// Get number of active sessions
  int get activeSessions => _authService.sessionCount;

  /// Check if authentication is required
  bool get authRequired => _authRequired;

  /// Check if in legacy mode (no users registered)
  bool get legacyMode => _legacyMode;
}
