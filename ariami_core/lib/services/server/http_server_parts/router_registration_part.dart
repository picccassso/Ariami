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
    _registerListeningStatsRoutes(router);
    _registerPinsRoutes(router);
    _registerPlaylistEditRoutes(router);
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

  void _registerPinsRoutes(Router router) {
    router.get(
      '/api/pins',
      (request) => _handleProtectedV2Request(request, _handlePinsGet),
    );
    router.post(
      '/api/pins',
      (request) => _handleProtectedV2Request(request, _handlePinsPost),
    );
    router.delete(
      '/api/pins/<type>/<targetId>',
      (request, type, targetId) => _handleProtectedV2Request(
        request,
        (securedRequest) => _handlePinsDelete(
          securedRequest,
          type,
          targetId,
        ),
      ),
    );
    router.post(
      '/api/pins/import',
      (request) => _handleProtectedV2Request(request, _handlePinsImport),
    );
  }

  void _registerPlaylistEditRoutes(Router router) {
    router.get(
      '/api/playlists/edits',
      (request) => _handleProtectedV2Request(request, _handlePlaylistEditsGet),
    );
    router.put(
      '/api/playlists/<playlistId>/edit',
      (request, playlistId) => _handleProtectedV2Request(
        request,
        (securedRequest) => _handlePlaylistEditPut(
          securedRequest,
          playlistId,
        ),
      ),
    );
    router.delete(
      '/api/playlists/<playlistId>/edit',
      (request, playlistId) => _handleProtectedV2Request(
        request,
        (securedRequest) => _handlePlaylistEditDelete(
          securedRequest,
          playlistId,
        ),
      ),
    );
  }

  void _registerCoreRoutes(Router router) {
    router.get('/api/ping', _handlePing);
    router.get('/api/tailscale/status', _handleTailscaleStatus);
    router.get('/api/server-info', _handleGetServerInfo);
    router.post('/api/server-info/refresh', _handleRefreshServerInfo);
  }

  /// Per-account listening statistics. Registered unconditionally (not gated
  /// on the v2 feature flag): they are session-scoped and independent of the
  /// catalog repository.
  void _registerListeningStatsRoutes(Router router) {
    router.post(
      '/api/v2/listening/events',
      (Request request) =>
          _handleProtectedV2Request(request, _handleListeningEventsPost),
    );
    router.get(
      '/api/v2/listening/summary',
      (Request request) =>
          _handleProtectedV2Request(request, _handleListeningSummaryGet),
    );
    router.get(
      '/api/v2/listening/daily',
      (Request request) =>
          _handleProtectedV2Request(request, _handleListeningDailyGet),
    );
    router.get(
      '/api/v2/listening/recent',
      (Request request) =>
          _handleProtectedV2Request(request, _handleListeningRecentGet),
    );
    router.post(
      '/api/v2/listening/reset',
      (Request request) =>
          _handleProtectedV2Request(request, _handleListeningResetPost),
    );
  }

  void _registerSetupAndStatsRoutes(Router router) {
    router.get('/api/setup/status', _handleGetSetupStatus);
    router.get('/api/setup/music-folder/suggestions',
        _handleGetMusicFolderSuggestions);
    router.post('/api/setup/music-folder/validate', _handleValidateMusicFolder);
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
    router.get('/api/auth/users', _handleAuthUsers);
    router.get('/api/auth/user-avatar/<username>', _handlePublicUserAvatar);
    router.post('/api/auth/login', _handleAuthLogin);
    router.post('/api/auth/logout', _handleAuthLogout);
    router.get('/api/me', _handleGetMe);
    router.put('/api/me/avatar', _handlePutMeAvatar);
    router.get('/api/me/avatar', _handleGetMeAvatar);
    router.delete('/api/me/avatar', _handleDeleteMeAvatar);
    router.post('/api/stream-ticket', _handleStreamTicket);
    router.post('/api/stream-warmup', _handleStreamWarmup);
    router.post('/api/download-ticket', _handleDownloadTicket);
    router.get('/api/admin/users', _handleAdminUsers);
    router.get('/api/admin/connected-clients', _handleAdminConnectedClients);
    router.get('/api/admin/user-activity', _handleAdminUserActivity);
    router.get('/api/admin/registration-token', _handleAdminRegistrationToken);
    router.get('/api/admin/invite-code', _handleAdminInviteCode);
    router.post('/api/admin/create-user', _handleAdminCreateUser);
    router.post('/api/admin/kick-client', _handleAdminKickClient);
    router.post('/api/admin/change-password', _handleAdminChangePassword);
    router.post('/api/admin/delete-user', _handleAdminDeleteUser);
    router.get('/api/admin/transcode-slots', _handleAdminGetTranscodeSlots);
    router.post('/api/admin/transcode-slots', _handleAdminPostTranscodeSlots);
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
