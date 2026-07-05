part of '../http_server.dart';

class _ServerInfoAuthSnapshot {
  const _ServerInfoAuthSnapshot({
    required this.hasUsers,
    required this.registeredUsers,
  });

  final bool hasUsers;
  final int registeredUsers;
}

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
  /// The transcoding service handles Sonic-based transcoding and caching.
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

  /// Set callback for periodic Tailscale/LAN endpoint discovery.
  void setEndpointDiscoveryCallback(
      Future<NetworkEndpoints> Function() callback) {
    _endpointDiscoveryCallback = callback;
    _ensureEndpointMonitor();
  }

  /// Stream of updated server-info payloads when advertised endpoints change.
  Stream<Map<String, dynamic>> get onEndpointsChanged =>
      _endpointsChangedController.stream;

  /// Update advertised endpoints without restarting the HTTP listener.
  ///
  /// Returns true when stored endpoint values changed.
  bool updateAdvertisedEndpoints({
    String? tailscaleIp,
    String? lanIp,
  }) {
    final previousTailscale = _tailscaleIp;
    final previousLan = _lanIp;
    final previousAdvertised = _advertisedIp;

    _tailscaleIp = tailscaleIp;
    _lanIp = lanIp;
    _advertisedIp = tailscaleIp ?? lanIp ?? _advertisedIp;

    if (previousTailscale == _tailscaleIp &&
        previousLan == _lanIp &&
        previousAdvertised == _advertisedIp) {
      return false;
    }

    print(
      '[HttpServer] Endpoints updated: tailscale=$_tailscaleIp lan=$_lanIp advertised=$_advertisedIp',
    );
    if (!_endpointsChangedController.isClosed) {
      _endpointsChangedController.add(getServerInfo());
    }
    return true;
  }

  /// Immediately re-run endpoint discovery instead of waiting for the poller.
  Future<Map<String, dynamic>> refreshAdvertisedEndpoints() async {
    final callback = _endpointDiscoveryCallback;
    if (callback == null) {
      return getServerInfo();
    }

    final endpoints = await callback();
    updateAdvertisedEndpoints(
      tailscaleIp: endpoints.tailscaleIp,
      lanIp: endpoints.lanIp,
    );
    return getServerInfo();
  }

  void _ensureEndpointMonitor() {
    final callback = _endpointDiscoveryCallback;
    if (callback == null) {
      return;
    }

    _endpointMonitor ??= NetworkEndpointMonitor(
      onChanged: (endpoints) {
        updateAdvertisedEndpoints(
          tailscaleIp: endpoints.tailscaleIp,
          lanIp: endpoints.lanIp,
        );
      },
    );
    _endpointMonitor!.setDiscoveryCallback(callback);

    if (_server != null) {
      _endpointMonitor!.start();
    }
  }

  void _stopEndpointMonitor() {
    _endpointMonitor?.stop();
  }

  /// Set setup operation callbacks (optional, for CLI use)
  void setSetupCallbacks({
    Future<String?> Function()? getConfiguredMusicFolderPath,
    Future<bool> Function(String)? setMusicFolder,
    Future<bool> Function()? startScan,
    Future<Map<String, dynamic>> Function()? getScanStatus,
    Future<bool> Function()? markSetupComplete,
    Future<bool> Function()? getSetupStatus,
  }) {
    _getConfiguredMusicFolderPathCallback = getConfiguredMusicFolderPath;
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

  /// Set callbacks for transcode slot configuration (CLI use).
  void setTranscodeSlotsCallbacks({
    Future<TranscodeSlotsSnapshot> Function()? getSnapshot,
    Future<TranscodeSlotsSnapshot> Function(int? slots)? setOverride,
  }) {
    _getTranscodeSlotsSnapshotCallback = getSnapshot;
    _setTranscodeSlotsOverrideCallback = setOverride;
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
      _pinnedItemStore?.close();
      _pinnedItemStore = null;
      _playlistEditStore?.close();
      _playlistEditStore = null;
      _userAvatarsDirectoryPath = null;
    }

    // Initialize AuthService with storage paths
    await _authService.initialize(usersFilePath, sessionsFilePath);
    _userAvatarsDirectoryPath =
        p.join(File(usersFilePath).parent.path, 'user_avatars');

    // Listening stats live next to the auth stores, keyed per user account.
    // Failure here must never block auth/startup: stats endpoints will report
    // 503 until the store becomes available.
    try {
      final statsDbPath =
          '${File(usersFilePath).parent.path}/listening_stats.db';
      final store = _listeningStatsStore ??
          ListeningStatsStore(databasePath: statsDbPath);
      store.initialize();
      _listeningStatsStore = store;
    } catch (e) {
      print('[HttpServer] Listening stats store unavailable: $e');
    }

    // Pins are durable account data and live beside the auth stores. A schema
    // creation here is the migration for existing Ariami installations.
    try {
      final pinsDbPath = '${File(usersFilePath).parent.path}/pinned_items.db';
      final store =
          _pinnedItemStore ?? PinnedItemStore(databasePath: pinsDbPath);
      store.initialize();
      _pinnedItemStore = store;
    } catch (e) {
      print('[HttpServer] Pinned items store unavailable: $e');
    }

    // Playlist edits are durable account data and live beside the auth stores.
    // They overlay folder-derived playlists without mutating the catalog.
    try {
      final playlistEditsDbPath =
          '${File(usersFilePath).parent.path}/playlist_edits.db';
      final store = _playlistEditStore ??
          PlaylistEditStore(databasePath: playlistEditsDbPath);
      store.initialize();
      _playlistEditStore = store;
    } catch (e) {
      print('[HttpServer] Playlist edit store unavailable: $e');
    }

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
        .addMiddleware(_authRateLimitMiddleware())
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
      _ensureEndpointMonitor();
    } catch (e) {
      print('Failed to start server: $e');
      rethrow;
    }
  }

  /// Start the HTTP server, trying [preferredPort] first and scanning 8080–8099
  /// when [allowFallback] is true.
  ///
  /// Returns the port the server is listening on.
  Future<int> startWithPortFallback({
    required String advertisedIp,
    String? tailscaleIp,
    String? lanIp,
    String bindAddress = '0.0.0.0',
    required int preferredPort,
    int? savedPort,
    bool allowFallback = true,
  }) async {
    if (_server != null) {
      await start(
        advertisedIp: advertisedIp,
        tailscaleIp: tailscaleIp,
        lanIp: lanIp,
        bindAddress: bindAddress,
        port: _port,
      );
      return _port;
    }

    final candidates = ServerPortPolicy.buildCandidates(
      preferredPort: preferredPort,
      savedPort: savedPort,
      allowFallback: allowFallback,
    );
    if (candidates.isEmpty) {
      throw PortBindingException(
        preferredPort: preferredPort,
        candidates: candidates,
        explicitPort: !allowFallback,
      );
    }

    final attemptedPort = candidates.first;
    for (final candidate in candidates) {
      try {
        await start(
          advertisedIp: advertisedIp,
          tailscaleIp: tailscaleIp,
          lanIp: lanIp,
          bindAddress: bindAddress,
          port: candidate,
        );
        _attemptedPort = attemptedPort;
        _portFallbackUsed = candidate != attemptedPort;
        return candidate;
      } catch (e) {
        if (ServerPortPolicy.isAddressInUseError(e)) {
          continue;
        }
        rethrow;
      }
    }

    throw PortBindingException(
      preferredPort: preferredPort,
      candidates: candidates,
      explicitPort: !allowFallback,
    );
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
    _stopEndpointMonitor();
    await _server?.close(force: true);
    _server = null;

    // Clear all connected clients since server is stopping
    _connectionManager.clearAll();

    // Close all WebSocket connections
    // Closing a socket synchronously triggers its onDone callback, which
    // removes it from _webSocketClients. Iterate over a snapshot so shutdown
    // cannot mutate the list currently being traversed.
    for (final client in List<WebSocketChannel>.of(_webSocketClients)) {
      try {
        await client.sink.close();
      } catch (e) {
        // Ignore errors when closing
      }
    }
    _webSocketClients.clear();
    _metricsService.stop();
    _inFlightDownloadTranscodesByUser.clear();
    _authEndpointAttempts.clear();
    _registrationTokens.clear();
    _streamTracker.dispose();

    print('Ariami Server stopped');
  }

  /// Get server info for QR code generation.
  ///
  /// Public `/api/server-info` must not include registration tokens. Local
  /// desktop/dashboard QR flows opt in so scanning the QR becomes the
  /// capability to create a non-admin mobile account.
  Map<String, dynamic> getServerInfo({bool includeRegistrationToken = false}) {
    final authSnapshot = _getAuthSnapshotForServerInfo();
    final info = {
      'server': _advertisedIp ?? _tailscaleIp,
      'lanServer': _lanIp,
      'tailscaleServer': _tailscaleIp,
      'port': _port,
      'attemptedPort': _attemptedPort ?? _port,
      'portFallbackUsed': _portFallbackUsed,
      'name': Platform.localHostname,
      'version': kAriamiVersion,
      'authRequired': _authRequired,
      'legacyMode': _legacyMode,
      'hasUsers': authSnapshot.hasUsers,
      'registeredUsers': authSnapshot.registeredUsers,
      'downloadLimits': {
        'maxConcurrent': _maxConcurrentDownloads,
        'maxQueue': _maxDownloadQueue,
        'maxConcurrentPerUser': _maxConcurrentDownloadsPerUser,
        'maxQueuePerUser': _maxDownloadQueuePerUser,
      },
    };
    if (includeRegistrationToken) {
      info.addAll(_createRegistrationTokenPayload());
    }
    return info;
  }

  Map<String, dynamic> _createRegistrationTokenPayload() {
    _purgeExpiredRegistrationTokens();
    final token = _generateRegistrationTokenValue();
    final expiresAt =
        DateTime.now().toUtc().add(AriamiHttpServer._registrationTokenTtl);
    _registrationTokens[token] = expiresAt;
    return {
      'registrationToken': token,
      'registrationTokenExpiresAt': expiresAt.toIso8601String(),
    };
  }

  /// Mint a short, single-use invite code for manual-entry registration.
  ///
  /// Public entry point for the in-process desktop app (which holds the server
  /// instance directly, with no HTTP round-trip). Returns `{ inviteCode,
  /// expiresAt }`.
  Map<String, dynamic> createInviteCode() => _createInviteCodePayload();

  /// Mint a short, single-use invite code for manual-entry registration.
  ///
  /// Stored in the same [_registrationTokens] map (same 10-min TTL, same
  /// single-use consumption on register) so it validates through the identical
  /// path as a QR registration token.
  Map<String, dynamic> _createInviteCodePayload() {
    _purgeExpiredRegistrationTokens();
    final code = _generateInviteCodeValue();
    final expiresAt =
        DateTime.now().toUtc().add(AriamiHttpServer._registrationTokenTtl);
    _registrationTokens[code] = expiresAt;
    return {
      'inviteCode': code,
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  bool _hasValidRegistrationToken(String? token) {
    _purgeExpiredRegistrationTokens();
    if (token == null || token.trim().isEmpty) {
      return false;
    }
    return _registrationTokens.containsKey(token.trim());
  }

  void _consumeRegistrationToken(String token) {
    _registrationTokens.remove(token.trim());
  }

  void _purgeExpiredRegistrationTokens() {
    final now = DateTime.now().toUtc();
    _registrationTokens.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
  }

  _ServerInfoAuthSnapshot _getAuthSnapshotForServerInfo() {
    try {
      return _ServerInfoAuthSnapshot(
        hasUsers: _authService.hasUsers(),
        registeredUsers: _authService.userCount,
      );
    } on StateError {
      return const _ServerInfoAuthSnapshot(
        hasUsers: false,
        registeredUsers: 0,
      );
    }
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
    if (flags.enableCatalogRead && !flags.enableV2Api) {
      throw StateError(
        'Invalid feature flag configuration: enableCatalogRead=true '
        'requires enableV2Api=true.',
      );
    }
    _featureFlags = flags;
    _libraryManager.setFeatureFlags(flags);
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

    if (_featureFlags.enableCatalogRead && !_featureFlags.enableV2Api) {
      throw StateError(
        'Invalid feature flag configuration: enableCatalogRead=true '
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

  void _incrementInFlightDownloadTranscode(String userId) {
    _inFlightDownloadTranscodesByUser[userId] =
        (_inFlightDownloadTranscodesByUser[userId] ?? 0) + 1;
  }

  void _decrementInFlightDownloadTranscode(String userId) {
    final next = (_inFlightDownloadTranscodesByUser[userId] ?? 0) - 1;
    if (next <= 0) {
      _inFlightDownloadTranscodesByUser.remove(userId);
      return;
    }
    _inFlightDownloadTranscodesByUser[userId] = next;
  }

  List<UserActivityRow> getActiveUserActivityRows() {
    final loadByUser = _downloadLimiter.userLoadByUser;
    final allUserIds = <String>{
      ...loadByUser.keys,
      ..._inFlightDownloadTranscodesByUser.keys,
    };

    final rows = <UserActivityRow>[];
    for (final userId in allUserIds) {
      final load = loadByUser[userId];
      final activeDownloads = load?.active ?? 0;
      final queuedDownloads = load?.queued ?? 0;
      final inFlightTranscodes = _inFlightDownloadTranscodesByUser[userId] ?? 0;

      final isDownloading = activeDownloads > 0 || queuedDownloads > 0;
      final isTranscoding = inFlightTranscodes > 0;

      if (!isDownloading && !isTranscoding) {
        continue;
      }

      rows.add(
        UserActivityRow(
          userId: userId,
          username: _resolveActivityUsername(userId),
          isDownloading: isDownloading,
          isTranscoding: isTranscoding,
          activeDownloads: activeDownloads,
          queuedDownloads: queuedDownloads,
          inFlightDownloadTranscodes: inFlightTranscodes,
        ),
      );
    }

    rows.sort((a, b) {
      final leftTotal =
          a.activeDownloads + a.queuedDownloads + a.inFlightDownloadTranscodes;
      final rightTotal =
          b.activeDownloads + b.queuedDownloads + b.inFlightDownloadTranscodes;
      final totalCompare = rightTotal.compareTo(leftTotal);
      if (totalCompare != 0) return totalCompare;

      final usernameCompare =
          a.username.toLowerCase().compareTo(b.username.toLowerCase());
      if (usernameCompare != 0) return usernameCompare;

      return a.userId.compareTo(b.userId);
    });

    return rows;
  }

  String _resolveActivityUsername(String userId) {
    if (userId == 'legacy') {
      return 'Legacy / Unauthenticated';
    }
    final username = _authService.getUserById(userId)?.username;
    if (username != null && username.trim().isNotEmpty) {
      return username.trim();
    }
    return 'Unknown User';
  }
}
