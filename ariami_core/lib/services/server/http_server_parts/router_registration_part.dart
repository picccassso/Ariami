part of '../http_server.dart';

extension AriamiHttpServerRouterMethods on AriamiHttpServer {
  /// Build the router with all API routes.
  Router _buildRouter() {
    final router = Router();
    final v2Handlers = AriamiV2Handlers(
      catalogRepositoryProvider: _libraryManager.createCatalogRepository,
    );
    final downloadJobService = DownloadJobService(
      catalogRepositoryProvider: _libraryManager.createCatalogRepository,
      maxQueuedItemsPerUser: max(
        _maxDownloadQueuePerUser,
        AriamiHttpServer._defaultMaxDownloadJobQueuePerUser,
      ),
    );

    _registerCoreRoutes(router);
    _registerSetupAndStatsRoutes(router);
    _registerAuthAndAdminRoutes(router);
    _registerLibraryAndArtworkRoutes(router);
    _registerConnectionRoutes(router);
    _registerMediaRoutes(router);
    _registerV2Routes(
      router,
      v2Handlers: v2Handlers,
      downloadJobService: downloadJobService,
    );
    _registerWebSocketRoutes(router);
    return router;
  }

  void _registerCoreRoutes(Router router) {
    router.get('/api/ping', _handlePing);
    router.get('/api/tailscale/status', _handleTailscaleStatus);
    router.get('/api/server-info', _handleGetServerInfo);
  }

  void _registerSetupAndStatsRoutes(Router router) {
    router.get('/api/setup/status', _handleGetSetupStatus);
    router.post('/api/setup/music-folder', _handleSetMusicFolder);
    router.post('/api/setup/start-scan', _handleStartScan);
    router.get('/api/setup/scan-status', _handleGetScanStatus);
    router.post('/api/setup/complete', _handleMarkSetupComplete);
    router.post(
      '/api/setup/transition-to-background',
      _handleTransitionToBackground,
    );
    router.get('/api/stats', _handleGetStats);
  }

  void _registerAuthAndAdminRoutes(Router router) {
    router.post('/api/auth/register', _handleAuthRegister);
    router.post('/api/auth/login', _handleAuthLogin);
    router.post('/api/auth/logout', _handleAuthLogout);
    router.get('/api/me', _handleGetMe);
    router.post('/api/stream-ticket', _handleStreamTicket);
    router.get('/api/admin/connected-clients', _handleAdminConnectedClients);
    router.post('/api/admin/kick-client', _handleAdminKickClient);
    router.post('/api/admin/change-password', _handleAdminChangePassword);
    router.post('/api/admin/delete-user', _handleAdminDeleteUser);
  }

  void _registerLibraryAndArtworkRoutes(Router router) {
    router.get('/api/albums', _handleGetAlbums);
    router.get('/api/albums/<albumId>', _handleGetAlbumDetail);
    router.get('/api/songs', _handleGetSongs);
    router.get('/api/artwork/<albumId>', _handleGetArtwork);
    router.get('/api/song-artwork/<songId>', _handleGetSongArtwork);
  }

  void _registerConnectionRoutes(Router router) {
    router.post('/api/connect', _handleConnect);
    router.post('/api/disconnect', _handleDisconnect);
  }

  void _registerMediaRoutes(Router router) {
    // Streaming endpoint - captures everything after /api/stream/
    router.get('/api/stream/<path|.*>', _handleStream);

    // Download endpoint - for downloading full audio files
    router.get('/api/download/<path|.*>', _handleDownload);
  }

  void _registerV2Routes(
    Router router, {
    required AriamiV2Handlers v2Handlers,
    required DownloadJobService downloadJobService,
  }) {
    if (!_featureFlags.enableV2Api) {
      return;
    }

    router.get(
      '/api/v2/bootstrap',
      (request) =>
          _handleProtectedV2Request(request, v2Handlers.handleBootstrap),
    );
    router.get(
      '/api/v2/albums',
      (request) => _handleProtectedV2Request(request, v2Handlers.handleAlbums),
    );
    router.get(
      '/api/v2/songs',
      (request) => _handleProtectedV2Request(request, v2Handlers.handleSongs),
    );
    router.get(
      '/api/v2/playlists',
      (request) =>
          _handleProtectedV2Request(request, v2Handlers.handlePlaylists),
    );
    router.get(
      '/api/v2/changes',
      (request) => _handleProtectedV2Request(request, v2Handlers.handleChanges),
    );

    if (!_featureFlags.enableDownloadJobs) {
      return;
    }

    router.post(
      '/api/v2/download-jobs',
      (request) => _handleProtectedV2Request(
        request,
        (securedRequest) =>
            _handleCreateDownloadJob(securedRequest, downloadJobService),
      ),
    );
    router.get(
      '/api/v2/download-jobs/<jobId>/items',
      (request, jobId) => _handleProtectedV2Request(
        request,
        (securedRequest) => _handleGetDownloadJobItems(
          securedRequest,
          jobId,
          downloadJobService,
        ),
      ),
    );
    router.post(
      '/api/v2/download-jobs/<jobId>/cancel',
      (request, jobId) => _handleProtectedV2Request(
        request,
        (securedRequest) => _handleCancelDownloadJob(
          securedRequest,
          jobId,
          downloadJobService,
        ),
      ),
    );
    router.get(
      '/api/v2/download-jobs/<jobId>',
      (request, jobId) => _handleProtectedV2Request(
        request,
        (securedRequest) =>
            _handleGetDownloadJob(securedRequest, jobId, downloadJobService),
      ),
    );
  }

  void _registerWebSocketRoutes(Router router) {
    // WebSocket endpoint
    router.get('/api/ws', webSocketHandler(_handleWebSocket));
  }
}
