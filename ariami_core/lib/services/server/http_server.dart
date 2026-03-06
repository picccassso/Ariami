import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:collection';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:crypto/crypto.dart';
import 'package:ariami_core/services/server/connection_manager.dart';
import 'package:ariami_core/services/server/streaming_service.dart';
import 'package:ariami_core/services/transcoding/transcoding_service.dart';
import 'package:ariami_core/services/artwork/artwork_service.dart';
import 'package:ariami_core/models/quality_preset.dart';
import 'package:ariami_core/models/artwork_size.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/library/library_manager.dart';
import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/auth/user_store.dart'
    show UserExistsException;
import 'package:ariami_core/models/auth_models.dart';
import 'package:ariami_core/models/download_job_models.dart';
import 'package:ariami_core/services/server/stream_tracker.dart';
import 'package:ariami_core/services/server/download_job_service.dart';
import 'package:ariami_core/services/server/metrics_service.dart';
import 'package:ariami_core/services/server/v2_handlers.dart';

/// HTTP server for Ariami desktop application (Singleton)
class AriamiHttpServer {
  // Singleton instance
  static final AriamiHttpServer _instance = AriamiHttpServer._internal();
  factory AriamiHttpServer() => _instance;
  AriamiHttpServer._internal() {
    _downloadLimiter = _WeightedFairDownloadLimiter(
      maxConcurrent: _maxConcurrentDownloads,
      maxQueue: _maxDownloadQueue,
      maxConcurrentPerUser: _maxConcurrentDownloadsPerUser,
      maxQueuePerUser: _maxDownloadQueuePerUser,
    );
  }

  HttpServer? _server;
  final ConnectionManager _connectionManager = ConnectionManager();
  final StreamingService _streamingService = StreamingService();
  final LibraryManager _libraryManager = LibraryManager();
  final AuthService _authService = AuthService();
  final StreamTracker _streamTracker = StreamTracker();
  TranscodingService? _transcodingService;
  ArtworkService? _artworkService;
  String? _tailscaleIp; // Kept for backward compatibility
  String? _advertisedIp; // The IP to show in QR code (Tailscale or LAN IP)
  int _port = 8080;
  final List<dynamic> _webSocketClients = [];
  final Map<dynamic, String> _webSocketDeviceIds = {};

  // Download concurrency controls (multi-user fairness)
  static const int _defaultMaxConcurrentDownloads = 4;
  static const int _defaultMaxDownloadQueue = 50;
  static const int _defaultMaxConcurrentDownloadsPerUser = 2;
  static const int _defaultMaxDownloadQueuePerUser = 20;
  int _maxConcurrentDownloads = _defaultMaxConcurrentDownloads;
  int _maxDownloadQueue = _defaultMaxDownloadQueue;
  int _maxConcurrentDownloadsPerUser = _defaultMaxConcurrentDownloadsPerUser;
  int _maxDownloadQueuePerUser = _defaultMaxDownloadQueuePerUser;
  late _WeightedFairDownloadLimiter _downloadLimiter;

  // Artwork request quotas (only enforced for server-managed artwork resizing).
  static const int _defaultMaxConcurrentArtworkPerUser = 2;
  static const int _defaultMaxArtworkQueuePerUser = 8;
  final Map<String, _SimpleLimiter> _artworkUserLimiters = {};
  static const int _defaultRetryAfterSeconds = 5;
  static const String _v1LibrarySunsetDate = '2026-06-30';
  static const String _v1LibrarySunsetHttpDate =
      'Tue, 30 Jun 2026 23:59:59 GMT';
  static const String _v1LibraryWarningHeader =
      '299 Ariami "/api/library is deprecated and reserved for legacy clients '
      'and CLI web screens. Migrate to /api/v2/* before 2026-06-30."';
  static const String _desktopDashboardAdminDeviceId =
      'desktop_dashboard_admin';
  static const String _desktopDashboardAdminDeviceName =
      'Ariami Desktop Dashboard';
  static const String _cliWebDashboardDeviceName = 'Ariami CLI Web Dashboard';
  static const String _clientTypeDashboard = 'dashboard';
  static const String _clientTypeUserDevice = 'user_device';
  static const String _clientTypeUnauthenticated = 'unauthenticated';
  bool _libraryListenersRegistered = false;
  void Function()? _scanCompleteListener;
  void Function()? _durationsReadyListener;

  // Store music folder path (set from desktop state)
  String? _musicFolderPath;

  // Auth flags for server info (multi-user support)
  bool _authRequired = false;
  bool _legacyMode = true;
  AriamiFeatureFlags _featureFlags = const AriamiFeatureFlags();
  final AriamiMetricsService _metricsService = AriamiMetricsService();
  int _lastBroadcastSyncToken = 0;
  final Random _secureRandom = Random.secure();

  // Store web assets path for serving static files
  String? _webAssetsPath;

  // Callback for getting Tailscale status (optional, for CLI use)
  Future<Map<String, dynamic>> Function()? _tailscaleStatusCallback;

  // Callbacks for setup operations (optional, for CLI use)
  Future<bool> Function(String path)? _setMusicFolderCallback;
  Future<bool> Function()? _startScanCallback;
  Future<Map<String, dynamic>> Function()? _getScanStatusCallback;
  Future<bool> Function()? _markSetupCompleteCallback;
  Future<bool> Function()? _getSetupStatusCallback;
  Future<Map<String, dynamic>> Function()? _transitionToBackgroundCallback;

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
    String bindAddress = '0.0.0.0',
    int port = 8080,
  }) async {
    // If already running, don't start again
    if (_server != null) {
      // Update stored IP/port even if server is already running
      _advertisedIp = advertisedIp;
      _tailscaleIp = advertisedIp; // Backward compatibility
      _port = port;
      print('Ariami Server already running on http://$_advertisedIp:$_port');
      return;
    }
    _advertisedIp = advertisedIp;
    _tailscaleIp = advertisedIp; // Backward compatibility
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
      _broadcastLibraryUpdated();
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
      'port': _port,
      'name': Platform.localHostname,
      'version': '3.0.0',
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

  /// Build the router with all API routes
  Router _buildRouter() {
    final router = Router();
    final v2Handlers = AriamiV2Handlers(
      catalogRepositoryProvider: _libraryManager.createCatalogRepository,
    );
    final downloadJobService = DownloadJobService(
      catalogRepositoryProvider: _libraryManager.createCatalogRepository,
      libraryManager: _libraryManager,
    );

    // Ping endpoint
    router.get('/api/ping', _handlePing);

    // Tailscale status endpoint
    router.get('/api/tailscale/status', _handleTailscaleStatus);

    // Setup endpoints
    router.get('/api/setup/status', _handleGetSetupStatus);
    router.post('/api/setup/music-folder', _handleSetMusicFolder);
    router.post('/api/setup/start-scan', _handleStartScan);
    router.get('/api/setup/scan-status', _handleGetScanStatus);
    router.post('/api/setup/complete', _handleMarkSetupComplete);
    router.post(
        '/api/setup/transition-to-background', _handleTransitionToBackground);

    // Stats endpoint (for dashboard)
    router.get('/api/stats', _handleGetStats);

    // Server info endpoint (for QR code generation)
    router.get('/api/server-info', _handleGetServerInfo);

    // Auth endpoints
    router.post('/api/auth/register', _handleAuthRegister);
    router.post('/api/auth/login', _handleAuthLogin);
    router.post('/api/auth/logout', _handleAuthLogout);
    router.get('/api/me', _handleGetMe);

    // Admin endpoints
    router.get('/api/admin/connected-clients', _handleAdminConnectedClients);
    router.post('/api/admin/kick-client', _handleAdminKickClient);
    router.post('/api/admin/change-password', _handleAdminChangePassword);

    // Stream ticket endpoint (for authenticated streaming)
    router.post('/api/stream-ticket', _handleStreamTicket);

    // Connection management
    router.post('/api/connect', _handleConnect);
    router.post('/api/disconnect', _handleDisconnect);

    // Library endpoints
    router.get('/api/library', _handleGetLibrary);
    router.get('/api/albums', _handleGetAlbums);
    router.get('/api/albums/<albumId>', _handleGetAlbumDetail);
    router.get('/api/songs', _handleGetSongs);
    router.get('/api/artwork/<albumId>', _handleGetArtwork);
    router.get('/api/song-artwork/<songId>', _handleGetSongArtwork);

    if (_featureFlags.enableV2Api) {
      router.get(
        '/api/v2/bootstrap',
        (request) =>
            _handleProtectedV2Request(request, v2Handlers.handleBootstrap),
      );
      router.get(
        '/api/v2/albums',
        (request) =>
            _handleProtectedV2Request(request, v2Handlers.handleAlbums),
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
        (request) =>
            _handleProtectedV2Request(request, v2Handlers.handleChanges),
      );

      if (_featureFlags.enableDownloadJobs) {
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
            (securedRequest) => _handleGetDownloadJob(
              securedRequest,
              jobId,
              downloadJobService,
            ),
          ),
        );
      }
    }

    // Streaming endpoint - captures everything after /api/stream/
    router.get('/api/stream/<path|.*>', _handleStream);

    // Download endpoint - for downloading full audio files
    router.get('/api/download/<path|.*>', _handleDownload);

    // WebSocket endpoint
    router.get('/api/ws', webSocketHandler(_handleWebSocket));

    return router;
  }

  /// CORS middleware
  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders());
        }

        final response = await handler(request);
        return response.change(headers: _corsHeaders());
      };
    };
  }

  /// CORS headers
  Map<String, String> _corsHeaders() {
    return {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };
  }

  /// Auth middleware - validates session tokens for protected endpoints
  Middleware _authMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final path = '/${request.url.path}';
        final isApiPath = path.startsWith('/api/');

        // Allow static web shell/assets when API-scoped auth is enabled.
        // API auth behavior remains unchanged.
        if (_featureFlags.enableApiScopedAuthForCliWeb && !isApiPath) {
          return await handler(request);
        }

        final isArtworkPath = path.startsWith('/api/artwork/') ||
            path.startsWith('/api/song-artwork/');

        // Public endpoints that don't require authentication
        final isPublicPath = path == '/api/ping' ||
            path == '/api/server-info' ||
            path == '/api/ws' ||
            path == '/api/stream' ||
            path.startsWith('/api/stream/') ||
            path == '/api/download' ||
            path.startsWith('/api/download/') ||
            path.startsWith('/api/auth/') ||
            path.startsWith('/api/setup/') ||
            path.startsWith('/api/tailscale/');

        if (isPublicPath) {
          return await handler(request);
        }

        // In legacy mode (no users registered), allow unauthenticated access
        if (_legacyMode && !_authService.hasUsers()) {
          return await handler(request);
        }

        // Artwork requests may use either:
        // 1) Session auth (Authorization header), or
        // 2) streamToken query param validated in artwork handlers.
        //
        // If there's no bearer auth on artwork routes, defer auth checks to
        // the handlers so notification artwork can authenticate via streamToken.
        final authHeader = request.headers['authorization'];
        if (isArtworkPath &&
            (authHeader == null || !authHeader.startsWith('Bearer '))) {
          return await handler(request);
        }

        // Extract session token from Authorization header
        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return _authRequiredResponse();
        }

        final sessionToken = authHeader.substring(7); // Remove 'Bearer ' prefix
        final session = await _authService.validateSession(sessionToken);

        if (session == null) {
          return _sessionExpiredResponse();
        }

        // Attach session to request context for use by handlers
        final updatedRequest = request.change(context: {
          ...request.context,
          'session': session,
        });

        return await handler(updatedRequest);
      };
    };
  }

  bool _isLegacyUnauthenticatedMode() {
    return _legacyMode && !_authService.hasUsers();
  }

  Response _authRequiredResponse() {
    return Response.unauthorized(
      jsonEncode({
        'error': {
          'code': AuthErrorCodes.authRequired,
          'message': 'Authentication required',
        },
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Response _forbiddenAdminResponse() {
    return Response.forbidden(
      jsonEncode({
        'error': {
          'code': AuthErrorCodes.forbiddenAdmin,
          'message': 'Admin privileges required',
        },
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Response _sessionExpiredResponse() {
    return Response.unauthorized(
      jsonEncode({
        'error': {
          'code': AuthErrorCodes.sessionExpired,
          'message': 'Session expired or invalid',
        },
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _handleProtectedV2Request(
    Request request,
    FutureOr<Response> Function(Request request) handler,
  ) async {
    if (_authRequired && !_isLegacyUnauthenticatedMode()) {
      final sessionFromContext = request.context['session'] as Session?;
      if (sessionFromContext == null) {
        final authHeader = request.headers['authorization'];
        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return _authRequiredResponse();
        }

        final sessionToken = authHeader.substring(7);
        final session = await _authService.validateSession(sessionToken);
        if (session == null) {
          return _sessionExpiredResponse();
        }

        request = request.change(context: {
          ...request.context,
          'session': session,
        });
      }
    }

    return await handler(request);
  }

  Response _forbiddenStreamTokenResponse(String message) {
    return Response.forbidden(
      jsonEncode({
        'error': {
          'code': AuthErrorCodes.streamTokenExpired,
          'message': message,
        },
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Response? _authorizeArtworkRequest(
    Request request, {
    String? requestedSongId,
    String? requestedAlbumId,
  }) {
    // In legacy mode with no users, artwork remains publicly accessible.
    if (!_authRequired || _isLegacyUnauthenticatedMode()) {
      return null;
    }

    // Session-authenticated request is already authorized.
    final session = request.context['session'] as Session?;
    if (session != null) {
      return null;
    }

    // No session: require a valid stream token.
    final streamToken = request.url.queryParameters['streamToken'];
    if (streamToken == null || streamToken.isEmpty) {
      return _forbiddenStreamTokenResponse('Stream token required');
    }

    final ticket = _streamTracker.validateToken(streamToken);
    if (ticket == null) {
      return _forbiddenStreamTokenResponse('Stream token expired or invalid');
    }

    if (requestedSongId != null && ticket.songId != requestedSongId) {
      return _forbiddenStreamTokenResponse(
        'Stream token does not match requested song artwork',
      );
    }

    if (requestedAlbumId != null) {
      final ticketSongAlbumId = _libraryManager.getSongAlbumId(ticket.songId);
      if (ticketSongAlbumId == null || ticketSongAlbumId != requestedAlbumId) {
        return _forbiddenStreamTokenResponse(
          'Stream token does not grant requested album artwork',
        );
      }
    }

    return null;
  }

  /// Middleware to refresh heartbeat for already-connected clients.
  /// This middleware must never implicitly register unknown clients.
  Middleware _connectionTrackingMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final deviceId = request.url.queryParameters['deviceId'];
        if (deviceId != null && deviceId.isNotEmpty) {
          final deviceName = request.url.queryParameters['deviceName'];
          final session = request.context['session'] as Session?;
          final userId = session?.userId;
          _connectionManager.refreshHeartbeatIfRegistered(
            deviceId,
            userId: userId,
            deviceName: deviceName,
          );
        }
        return await handler(request);
      };
    };
  }

  /// Error handling middleware
  Middleware _errorMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        try {
          return await handler(request);
        } on HijackException {
          // WebSocket upgrade uses hijack control flow. Let Shelf adapter handle it.
          rethrow;
        } catch (e, stackTrace) {
          print('Error handling request: $e');
          print('Stack trace: $stackTrace');
          return Response.internalServerError(
            body: jsonEncode({
              'error': 'Internal server error',
              'message': e.toString(),
            }),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
          );
        }
      };
    };
  }

  /// Metrics middleware for endpoint latency/payload and queue/token snapshots.
  Middleware _metricsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final stopwatch = Stopwatch()..start();
        final response = await handler(request);
        stopwatch.stop();

        final normalizedPath = _normalizeMetricsPath(request.url.path);
        final payloadBytes = _resolveResponsePayloadBytes(response);
        _metricsService.recordEndpoint(
          method: request.method,
          path: normalizedPath,
          statusCode: response.statusCode,
          latencyMs: stopwatch.elapsedMilliseconds,
          payloadBytes: payloadBytes,
        );

        final isArtworkRequest = normalizedPath == '/api/artwork/:albumId' ||
            normalizedPath == '/api/song-artwork/:songId';
        if (isArtworkRequest) {
          _metricsService.recordArtworkCacheRequest(
            cacheHit: response.statusCode == HttpStatus.notModified,
          );
        }

        _captureQueueAndLagMetrics();
        return response;
      };
    };
  }

  void _captureQueueAndLagMetrics() {
    final artworkQueueDepthByUser = <String, int>{};
    _artworkUserLimiters.forEach((userId, limiter) {
      if (limiter.queueLength > 0) {
        artworkQueueDepthByUser[userId] = limiter.queueLength;
      }
    });

    _metricsService.recordQueueDepth(
      downloadQueueDepthByUser: _downloadLimiter.queueDepthByUser,
      artworkQueueDepthByUser: artworkQueueDepthByUser,
    );

    final latestToken = _libraryManager.latestToken;
    final lagTokens = max(0, latestToken - _lastBroadcastSyncToken);
    _metricsService.recordLibraryChangesLag(
      lagTokens: lagTokens,
      latestToken: latestToken,
      broadcastToken: _lastBroadcastSyncToken,
    );
  }

  String _normalizeMetricsPath(String rawPath) {
    final path = rawPath.startsWith('/') ? rawPath : '/$rawPath';

    if (path.startsWith('/api/artwork/')) {
      return '/api/artwork/:albumId';
    }
    if (path.startsWith('/api/song-artwork/')) {
      return '/api/song-artwork/:songId';
    }
    if (path.startsWith('/api/albums/') && path != '/api/albums') {
      return '/api/albums/:albumId';
    }
    if (path.startsWith('/api/stream/')) {
      return '/api/stream/:songId';
    }
    if (path.startsWith('/api/download/')) {
      return '/api/download/:songId';
    }
    if (path.startsWith('/api/v2/download-jobs/')) {
      if (path.endsWith('/items')) {
        return '/api/v2/download-jobs/:jobId/items';
      }
      if (path.endsWith('/cancel')) {
        return '/api/v2/download-jobs/:jobId/cancel';
      }
      return '/api/v2/download-jobs/:jobId';
    }
    return path;
  }

  int? _resolveResponsePayloadBytes(Response response) {
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength >= 0) {
      return contentLength;
    }

    final headerValue = response.headers['content-length'];
    if (headerValue == null || headerValue.isEmpty) {
      return null;
    }
    return int.tryParse(headerValue);
  }

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
        'version': '3.0.0',
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
      return _clientTypeDashboard;
    }
    if (client.userId == null) {
      return _clientTypeUnauthenticated;
    }
    return _clientTypeUserDevice;
  }

  bool _isDashboardControlClient({
    required String deviceId,
    required String deviceName,
  }) {
    if (deviceId == _desktopDashboardAdminDeviceId) {
      return true;
    }
    return deviceName == _desktopDashboardAdminDeviceName ||
        deviceName == _cliWebDashboardDeviceName;
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

  String _generateDeviceId() {
    final nonce = _generateHexNonce(8);
    return 'device_${DateTime.now().millisecondsSinceEpoch}_$nonce';
  }

  String _generateHexNonce(int byteCount) {
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      final byte = _secureRandom.nextInt(256);
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Handle client connection
  Future<Response> _handleConnect(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final rawDeviceId = data['deviceId'] as String?;
      final rawDeviceName = data['deviceName'] as String?;

      final deviceName = (rawDeviceName == null || rawDeviceName.isEmpty)
          ? 'Unknown Device'
          : rawDeviceName;

      String deviceId = rawDeviceId?.trim() ?? '';
      if (deviceId.isEmpty || deviceId == 'unknown-device') {
        deviceId = _generateDeviceId();
      }

      final session = request.context['session'] as Session?;
      final userId = session?.userId;

      _connectionManager.registerOrRefreshClient(
        deviceId,
        deviceName,
        userId: userId,
      );

      // Broadcast client connection to all WebSocket clients
      broadcastWebSocketMessage(ClientConnectedMessage(
        clientCount: _connectionManager.clientCount,
        deviceName: deviceName,
      ));

      // Generate session ID
      final sessionId =
          'session_${DateTime.now().millisecondsSinceEpoch}_$deviceId';

      return Response.ok(
        jsonEncode({
          'status': 'connected',
          'sessionId': sessionId,
          'serverVersion': '3.0.0',
          'features': ['library', 'streaming', 'websocket'],
          'deviceId': deviceId,
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': e.toString(),
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle client disconnection.
  /// In auth mode, uses bearer session context.
  /// In legacy mode, expects deviceId in request body.
  Future<Response> _handleDisconnect(Request request) async {
    try {
      final body = await request.readAsString();
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      final deviceId = data['deviceId'] as String?;
      final session = request.context['session'] as Session?;

      late final String resolvedDeviceId;
      String? deviceName;

      if (_authRequired && !_legacyMode) {
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

        resolvedDeviceId = session.deviceId;
        // Disconnect is a presence change only - do NOT revoke auth session
        // or stream tickets. Session remains valid for reconnection.
        // Explicit logout (/api/auth/logout) and admin actions still revoke.
      } else {
        if (deviceId == null || deviceId.isEmpty) {
          return Response.badRequest(
            body: jsonEncode({
              'error': 'Missing required field',
              'message': 'deviceId is required',
            }),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
          );
        }
        resolvedDeviceId = deviceId;
      }

      // Get client name before unregistering
      final client = _connectionManager.getClient(resolvedDeviceId);
      deviceName = client?.deviceName;
      _connectionManager.unregisterClient(resolvedDeviceId);

      // Broadcast client disconnection to all WebSocket clients
      broadcastWebSocketMessage(ClientDisconnectedMessage(
        clientCount: _connectionManager.clientCount,
        deviceName: deviceName,
      ));

      return Response.ok(
        jsonEncode({
          'status': 'disconnected',
          'deviceId': resolvedDeviceId,
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': e.toString(),
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Handle get library request
  Future<Response> _handleGetLibrary(Request request) async {
    final userAgent = request.headers['user-agent'] ?? 'unknown';
    print('[HttpServer][WARN] Deprecated /api/library snapshot requested by '
        '"$userAgent". Reserved for legacy clients and CLI web screens. '
        'Sunset date: $_v1LibrarySunsetDate.');

    final baseUrl = 'http://${_advertisedIp ?? _tailscaleIp}:$_port';
    final stopwatch = Stopwatch()..start();
    final libraryJson = _libraryManager.toApiJson(baseUrl);
    stopwatch.stop();

    final durationsReady = libraryJson['durationsReady'] as bool? ?? true;
    if (!durationsReady) {
      _libraryManager.ensureDurationWarmup();
    }

    // Debug logging
    print(
        '[HttpServer] Library response built in ${stopwatch.elapsedMilliseconds}ms');
    print(
        '[HttpServer] Library request - Albums: ${(libraryJson['albums'] as List).length}, Songs: ${(libraryJson['songs'] as List).length}, durationsReady: $durationsReady');
    print(
        '[HttpServer] Library manager has library: ${_libraryManager.library != null}');
    print('[HttpServer] Last scan time: ${_libraryManager.lastScanTime}');

    return Response.ok(
      jsonEncode(libraryJson),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Deprecation': 'true',
        'Sunset': _v1LibrarySunsetHttpDate,
        'Warning': _v1LibraryWarningHeader,
      },
    );
  }

  /// Handle get albums request (placeholder for Phase 5)
  Response _handleGetAlbums(Request request) {
    return Response.ok(
      jsonEncode({
        'albums': [],
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  /// Handle get songs request (placeholder for Phase 5)
  Response _handleGetSongs(Request request) {
    return Response.ok(
      jsonEncode({
        'songs': [],
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _handleCreateDownloadJob(
    Request request,
    DownloadJobService downloadJobService,
  ) async {
    try {
      final body = await request.readAsString();
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      final createRequest = DownloadJobCreateRequest.fromJson(data);
      final response = downloadJobService.createJob(
        userScopeId: _resolveDownloadJobScopeUserId(request),
        request: createRequest,
      );
      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on DownloadJobServiceException catch (e) {
      return _downloadJobErrorResponse(e);
    } on FormatException {
      return _downloadJobErrorResponse(
        const DownloadJobServiceException(
          statusCode: 400,
          code: DownloadJobErrorCodes.invalidRequest,
          message: 'Invalid JSON body',
        ),
      );
    } on TypeError {
      return _downloadJobErrorResponse(
        const DownloadJobServiceException(
          statusCode: 400,
          code: DownloadJobErrorCodes.invalidRequest,
          message: 'Invalid request body',
        ),
      );
    }
  }

  Response _handleGetDownloadJob(
    Request request,
    String jobId,
    DownloadJobService downloadJobService,
  ) {
    try {
      final response = downloadJobService.getJob(
        userScopeId: _resolveDownloadJobScopeUserId(request),
        jobId: jobId,
      );
      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on DownloadJobServiceException catch (e) {
      return _downloadJobErrorResponse(e);
    }
  }

  Response _handleGetDownloadJobItems(
    Request request,
    String jobId,
    DownloadJobService downloadJobService,
  ) {
    final rawCursor = request.url.queryParameters['cursor'];
    final rawLimit = request.url.queryParameters['limit'];

    final cursor =
        rawCursor == null || rawCursor.isEmpty ? null : int.tryParse(rawCursor);
    if (rawCursor != null && rawCursor.isNotEmpty && cursor == null) {
      return _downloadJobErrorResponse(
        const DownloadJobServiceException(
          statusCode: 400,
          code: DownloadJobErrorCodes.invalidCursor,
          message: 'cursor must be a non-negative integer',
        ),
      );
    }

    final limit = rawLimit == null || rawLimit.isEmpty
        ? DownloadJobService.defaultPageLimit
        : int.tryParse(rawLimit);
    if (rawLimit != null && rawLimit.isNotEmpty && limit == null) {
      return _downloadJobErrorResponse(
        const DownloadJobServiceException(
          statusCode: 400,
          code: DownloadJobErrorCodes.invalidRequest,
          message: 'limit must be an integer between 1 and 500',
        ),
      );
    }

    try {
      final response = downloadJobService.getJobItems(
        userScopeId: _resolveDownloadJobScopeUserId(request),
        jobId: jobId,
        cursor: cursor,
        limit: limit ?? DownloadJobService.defaultPageLimit,
      );
      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on DownloadJobServiceException catch (e) {
      return _downloadJobErrorResponse(e);
    }
  }

  Response _handleCancelDownloadJob(
    Request request,
    String jobId,
    DownloadJobService downloadJobService,
  ) {
    try {
      final response = downloadJobService.cancelJob(
        userScopeId: _resolveDownloadJobScopeUserId(request),
        jobId: jobId,
      );
      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on DownloadJobServiceException catch (e) {
      return _downloadJobErrorResponse(e);
    }
  }

  String _resolveDownloadJobScopeUserId(Request request) {
    final session = request.context['session'] as Session?;
    return session?.userId ?? 'legacy';
  }

  Response _downloadJobErrorResponse(DownloadJobServiceException error) {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (error.statusCode == 429 || error.statusCode == 503) {
      headers['Retry-After'] =
          '${error.retryAfterSeconds ?? _defaultRetryAfterSeconds}';
    }

    return Response(
      error.statusCode,
      body: jsonEncode({
        'error': {
          'code': error.code,
          'message': error.message,
          if (error.details != null) 'details': error.details,
        },
      }),
      headers: headers,
    );
  }

  Response _retryableErrorResponse({
    required int statusCode,
    required String error,
    required String message,
    int retryAfterSeconds = _defaultRetryAfterSeconds,
  }) {
    return Response(
      statusCode,
      body: jsonEncode({
        'error': error,
        'message': message,
      }),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Retry-After': '$retryAfterSeconds',
      },
    );
  }

  String? _resolveRequestUserId(Request request) {
    final session = request.context['session'] as Session?;
    if (session != null) {
      return session.userId;
    }

    final streamToken = request.url.queryParameters['streamToken'];
    if (streamToken == null || streamToken.isEmpty) {
      return null;
    }

    final ticket = _streamTracker.validateToken(streamToken);
    return ticket?.userId;
  }

  /// Handle get album detail request
  Future<Response> _handleGetAlbumDetail(
      Request request, String albumId) async {
    final baseUrl = 'http://${_advertisedIp ?? _tailscaleIp}:$_port';
    final albumDetail = await _libraryManager.getAlbumDetail(albumId, baseUrl);

    if (albumDetail == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'ALBUM_NOT_FOUND',
            'message': 'Album not found: $albumId',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    return Response.ok(
      jsonEncode(albumDetail),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  /// Handle get album artwork request (lazy extraction with caching)
  ///
  /// Supports optional `?size=` parameter:
  /// - `thumbnail` - Returns a 200x200 thumbnail (faster for list views)
  /// - `full` or omitted - Returns the original artwork
  Future<Response> _handleGetArtwork(Request request, String albumId) async {
    final authResponse = _authorizeArtworkRequest(
      request,
      requestedAlbumId: albumId,
    );
    if (authResponse != null) {
      return authResponse;
    }

    // Parse size parameter (default: full for backward compatibility)
    final sizeParam = request.url.queryParameters['size'];
    final size = ArtworkSize.fromString(sizeParam);

    final artworkData = await _libraryManager.getAlbumArtwork(albumId);

    if (artworkData == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'ARTWORK_NOT_FOUND',
            'message': 'Artwork not found for album: $albumId',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final shouldApplyArtworkQuota = size.requiresProcessing &&
        _artworkService != null &&
        _authRequired &&
        !_isLegacyUnauthenticatedMode();
    String? artworkUserId;
    _SimpleLimiter? artworkLimiter;
    if (shouldApplyArtworkQuota) {
      artworkUserId = _resolveRequestUserId(request);
      if (artworkUserId != null) {
        artworkLimiter = _artworkUserLimiters.putIfAbsent(
          artworkUserId,
          () => _SimpleLimiter(
            maxConcurrent: _defaultMaxConcurrentArtworkPerUser,
            maxQueue: _defaultMaxArtworkQueuePerUser,
          ),
        );
        final acquired = await artworkLimiter.acquire();
        if (!acquired) {
          return _retryableErrorResponse(
            statusCode: 429,
            error: 'Too many artwork requests',
            message: 'Per-user artwork request queue is full',
          );
        }
      }
    }

    List<int> responseData = artworkData;
    try {
      // Process artwork if size requested and service available
      if (size.requiresProcessing && _artworkService != null) {
        responseData =
            await _artworkService!.getArtwork(albumId, artworkData, size);
        print(
            '[HttpServer] Serving ${size.name} artwork for album $albumId (${responseData.length} bytes)');
      }
    } finally {
      if (artworkUserId != null && artworkLimiter != null) {
        artworkLimiter.release();
        if (artworkLimiter.isIdle) {
          _artworkUserLimiters.remove(artworkUserId);
        }
      }
    }

    final etag = _computeArtworkEtag(responseData);
    final quotedEtag = '"$etag"';
    final lastModified = _resolveArtworkLastModified();
    final lastModifiedHttp = HttpDate.format(lastModified);
    final ifNoneMatch = request.headers['if-none-match'];
    if (_isMatchingEtag(ifNoneMatch, etag)) {
      return Response.notModified(
        headers: {
          'ETag': quotedEtag,
          'Last-Modified': lastModifiedHttp,
          'Cache-Control': 'public, max-age=31536000',
          'X-Artwork-Size': size.name,
        },
      );
    }

    // Return the image data (usually JPEG or PNG)
    return Response.ok(
      responseData,
      headers: {
        'Content-Type': 'image/jpeg', // Most album art is JPEG
        'Cache-Control': 'public, max-age=31536000', // Cache for 1 year
        'ETag': quotedEtag,
        'Last-Modified': lastModifiedHttp,
        'X-Artwork-Size': size.name, // Debug header
      },
    );
  }

  /// Handle get song artwork request (for standalone songs)
  ///
  /// Supports optional `?size=` parameter:
  /// - `thumbnail` - Returns a 200x200 thumbnail (faster for list views)
  /// - `full` or omitted - Returns the original artwork
  Future<Response> _handleGetSongArtwork(Request request, String songId) async {
    final authResponse = _authorizeArtworkRequest(
      request,
      requestedSongId: songId,
    );
    if (authResponse != null) {
      return authResponse;
    }

    // Parse size parameter (default: full for backward compatibility)
    final sizeParam = request.url.queryParameters['size'];
    final size = ArtworkSize.fromString(sizeParam);

    final artworkData = await _libraryManager.getSongArtwork(songId);

    if (artworkData == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'ARTWORK_NOT_FOUND',
            'message': 'Artwork not found for song: $songId',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final shouldApplyArtworkQuota = size.requiresProcessing &&
        _artworkService != null &&
        _authRequired &&
        !_isLegacyUnauthenticatedMode();
    String? artworkUserId;
    _SimpleLimiter? artworkLimiter;
    if (shouldApplyArtworkQuota) {
      artworkUserId = _resolveRequestUserId(request);
      if (artworkUserId != null) {
        artworkLimiter = _artworkUserLimiters.putIfAbsent(
          artworkUserId,
          () => _SimpleLimiter(
            maxConcurrent: _defaultMaxConcurrentArtworkPerUser,
            maxQueue: _defaultMaxArtworkQueuePerUser,
          ),
        );
        final acquired = await artworkLimiter.acquire();
        if (!acquired) {
          return _retryableErrorResponse(
            statusCode: 429,
            error: 'Too many artwork requests',
            message: 'Per-user artwork request queue is full',
          );
        }
      }
    }

    // Use songId as the cache key for song artwork
    List<int> responseData = artworkData;
    try {
      // Process artwork if size requested and service available
      if (size.requiresProcessing && _artworkService != null) {
        responseData = await _artworkService!
            .getArtwork('song_$songId', artworkData, size);
        print(
            '[HttpServer] Serving ${size.name} artwork for song $songId (${responseData.length} bytes)');
      }
    } finally {
      if (artworkUserId != null && artworkLimiter != null) {
        artworkLimiter.release();
        if (artworkLimiter.isIdle) {
          _artworkUserLimiters.remove(artworkUserId);
        }
      }
    }

    final etag = _computeArtworkEtag(responseData);
    final quotedEtag = '"$etag"';
    final lastModified = _resolveArtworkLastModified();
    final lastModifiedHttp = HttpDate.format(lastModified);
    final ifNoneMatch = request.headers['if-none-match'];
    if (_isMatchingEtag(ifNoneMatch, etag)) {
      return Response.notModified(
        headers: {
          'ETag': quotedEtag,
          'Last-Modified': lastModifiedHttp,
          'Cache-Control': 'public, max-age=31536000',
          'X-Artwork-Size': size.name,
        },
      );
    }

    // Return the image data (usually JPEG or PNG)
    return Response.ok(
      responseData,
      headers: {
        'Content-Type': 'image/jpeg', // Most album art is JPEG
        'Cache-Control': 'public, max-age=31536000', // Cache for 1 year
        'ETag': quotedEtag,
        'Last-Modified': lastModifiedHttp,
        'X-Artwork-Size': size.name, // Debug header
      },
    );
  }

  String _computeArtworkEtag(List<int> artworkBytes) {
    return md5.convert(artworkBytes).toString();
  }

  DateTime _resolveArtworkLastModified() {
    return (_libraryManager.lastScanTime ?? DateTime.now()).toUtc();
  }

  bool _isMatchingEtag(String? ifNoneMatchHeader, String etag) {
    if (ifNoneMatchHeader == null || ifNoneMatchHeader.trim().isEmpty) {
      return false;
    }

    final values = ifNoneMatchHeader
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);

    for (final value in values) {
      if (value == '*') {
        return true;
      }
      var candidate = value;
      if (candidate.startsWith('W/')) {
        candidate = candidate.substring(2);
      }
      if (candidate.startsWith('"') &&
          candidate.endsWith('"') &&
          candidate.length >= 2) {
        candidate = candidate.substring(1, candidate.length - 1);
      }
      if (candidate == etag) {
        return true;
      }
    }

    return false;
  }

  /// Handle stream request
  ///
  /// Supports quality parameter for transcoded streaming:
  /// - ?quality=high (default) - Original file
  /// - ?quality=medium - 128 kbps AAC
  /// - ?quality=low - 64 kbps AAC
  Future<Response> _handleStream(Request request, String path) async {
    // Validate path is provided
    if (path.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': 'Song ID is required',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    // Validate stream token if auth is required
    String? streamToken;
    if (_authRequired && !_legacyMode) {
      streamToken = request.url.queryParameters['streamToken'];
      if (streamToken == null || streamToken.isEmpty) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final ticket = _streamTracker.validateToken(streamToken);
      if (ticket == null) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token expired or invalid',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // Verify the token is for the requested song
      if (ticket.songId != path) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token does not match requested song',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // Mark stream as active for stats tracking
      _streamTracker.startStream(streamToken);
    }

    // Parse quality parameter
    final qualityParam = request.url.queryParameters['quality'];
    final quality = QualityPreset.fromString(qualityParam);

    // Look up file path from library by song ID
    final filePath = _libraryManager.getSongFilePath(path);
    if (filePath == null) {
      return Response.notFound(
        jsonEncode({
          'error': 'Song not found',
          'message': 'Song ID not found in library: $path',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final File originalFile = File(filePath);

    // Check if file exists
    if (!await originalFile.exists()) {
      return Response.notFound(
        jsonEncode({
          'error': 'File not found',
          'message': 'Audio file does not exist: $path',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    // Check if file is in allowed music folder (security check)
    if (_musicFolderPath != null) {
      final canonicalPath = originalFile.absolute.path;
      if (!canonicalPath.startsWith(_musicFolderPath!)) {
        return Response.forbidden(
          jsonEncode({
            'error': 'Forbidden',
            'message': 'File is outside music library',
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    }

    // Determine which file to stream
    File fileToStream = originalFile;

    // If transcoding is requested and service is available
    if (quality.requiresTranscoding && _transcodingService != null) {
      // Try streaming transcode first for immediate playback (no wait for full transcode)
      final streamResult = await _transcodingService!.startStreamingTranscode(
        filePath,
        path, // songId
        quality,
      );

      if (streamResult != null) {
        // Return streaming response directly - playback starts immediately
        print(
            '[HttpServer] Streaming transcode started for $path at ${quality.name}');
        return Response.ok(
          streamResult.stream,
          headers: {
            'Content-Type': streamResult.mimeType,
            'Transfer-Encoding': 'chunked',
            'Cache-Control': 'no-cache',
          },
        );
      }

      // Fall back to cached/queued transcode
      final transcodedFile = await _transcodingService!.getTranscodedFile(
        filePath,
        path, // songId
        quality,
        requestType: TranscodeRequestType.streaming,
      );

      if (transcodedFile != null) {
        fileToStream = transcodedFile;
        // Mark as in-use to prevent eviction during streaming
        _transcodingService!.markInUse(path, quality);
        print(
            '[HttpServer] Streaming transcoded file at ${quality.name} quality');

        // Stream the file and release in-use when done
        try {
          return await _streamingService.streamFile(fileToStream, request);
        } finally {
          _transcodingService!.releaseInUse(path, quality);
        }
      } else {
        // Transcoding failed or FFmpeg not available - fall back to original
        print(
            '[HttpServer] Transcoding unavailable, falling back to original file');
      }
    } else if (quality.requiresTranscoding && _transcodingService == null) {
      print(
          '[HttpServer] Transcoding requested but service not configured, using original');
    }

    // Stream the file (original or non-transcoded)
    return await _streamingService.streamFile(fileToStream, request);
  }

  /// Handle download request (full file download)
  ///
  /// Supports quality parameter for transcoded downloads:
  /// - ?quality=high (default) - Original file
  /// - ?quality=medium - 128 kbps AAC
  /// - ?quality=low - 64 kbps AAC
  Future<Response> _handleDownload(Request request, String path) async {
    // Validate path is provided
    if (path.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': 'Song ID is required',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    // Validate stream token if auth is required
    String? userId;
    if (_authRequired && !_legacyMode) {
      final streamToken = request.url.queryParameters['streamToken'];
      if (streamToken == null || streamToken.isEmpty) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final ticket = _streamTracker.validateToken(streamToken);
      if (ticket == null) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token expired or invalid',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // Verify the token is for the requested song
      if (ticket.songId != path) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token does not match requested song',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      userId = ticket.userId;
    }

    // Parse quality parameter
    final qualityParam = request.url.queryParameters['quality'];
    final quality = QualityPreset.fromString(qualityParam);

    // Look up file path from library by song ID
    final filePath = _libraryManager.getSongFilePath(path);
    if (filePath == null) {
      return Response.notFound(
        jsonEncode({
          'error': 'Song not found',
          'message': 'Song ID not found in library: $path',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final File originalFile = File(filePath);

    // Check if file exists
    if (!await originalFile.exists()) {
      return Response.notFound(
        jsonEncode({
          'error': 'File not found',
          'message': 'Audio file does not exist: $path',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    // Check if file is in allowed music folder (security check)
    if (_musicFolderPath != null) {
      final canonicalPath = originalFile.absolute.path;
      if (!canonicalPath.startsWith(_musicFolderPath!)) {
        return Response.forbidden(
          jsonEncode({
            'error': 'Forbidden',
            'message': 'File is outside music library',
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    }

    // Enforce weighted-fair download limits across users.
    final userKey = userId ?? 'legacy';
    final acquireResult = await _downloadLimiter.acquire(userKey);
    if (acquireResult == _FairAcquireResult.userQuotaExceeded) {
      print(
          '[HttpServer] Download rejected (user queue full) userId=$userKey songId=$path');
      return _retryableErrorResponse(
        statusCode: 429,
        error: 'Too many downloads for user',
        message: 'Per-user download queue is full',
      );
    }
    if (acquireResult == _FairAcquireResult.queueFull) {
      print(
          '[HttpServer] Download rejected (queue full) userId=$userKey songId=$path '
          'active=${_downloadLimiter.activeCount} queue=${_downloadLimiter.queueLength}');
      return _retryableErrorResponse(
        statusCode: 503,
        error: 'Server busy',
        message: 'Download queue is full, try again later',
      );
    }

    bool releaseOnError = true;

    try {
      // Determine which file to download
      File fileToDownload = originalFile;
      String mimeType = _streamingService.getAudioMimeType(originalFile.path);
      DownloadTranscodeResult? downloadTranscodeResult;

      // If transcoding is requested and service is available
      if (quality.requiresTranscoding && _transcodingService != null) {
        // Use dedicated download pipeline (temp file, not cached)
        // This prevents cache churn during bulk downloads
        downloadTranscodeResult =
            await _transcodingService!.getDownloadTranscode(
          filePath,
          path, // songId
          quality,
        );

        if (downloadTranscodeResult != null) {
          fileToDownload = downloadTranscodeResult.tempFile;
          mimeType = quality.mimeType ?? mimeType;
          print(
              '[HttpServer] Downloading transcoded file at ${quality.name} quality (temp file)');
        } else {
          // Transcoding failed or FFmpeg not available - fall back to original
          print(
              '[HttpServer] Transcoding unavailable for download, falling back to original file');
        }
      } else if (quality.requiresTranscoding && _transcodingService == null) {
        print(
            '[HttpServer] Transcoding requested for download but service not configured, using original');
      }

      // Get file info
      final fileSize = await fileToDownload.length();
      final originalFileName =
          originalFile.path.split(Platform.pathSeparator).last;

      // Adjust filename extension if transcoded
      String downloadFileName = originalFileName;
      if (downloadTranscodeResult != null && quality.fileExtension != null) {
        // Replace extension with transcoded format extension
        final lastDot = originalFileName.lastIndexOf('.');
        if (lastDot > 0) {
          downloadFileName =
              '${originalFileName.substring(0, lastDot)}.${quality.fileExtension}';
        } else {
          downloadFileName = '$originalFileName.${quality.fileExtension}';
        }
      }

      // Open file with explicit handle management to prevent file handle leaks
      final RandomAccessFile raf =
          await fileToDownload.open(mode: FileMode.read);

      // Capture the result for cleanup in the stream's finally block
      final tempResult = downloadTranscodeResult;

      // Create stream that properly closes the file handle and cleans up temp files when done
      Stream<List<int>> createFileStream() async* {
        const int chunkSize = 64 * 1024; // 64 KB chunks
        try {
          while (true) {
            final chunk = await raf.read(chunkSize);
            if (chunk.isEmpty) break;
            yield chunk;
          }
        } finally {
          await raf.close();
          // Clean up temp file after download completes
          if (tempResult != null) {
            await tempResult.cleanup();
            print('[HttpServer] Cleaned up temp transcode file');
          }
          _releaseDownloadSlot(userKey);
        }
      }

      // Return the file as a download with appropriate headers
      releaseOnError = false;
      return Response.ok(
        createFileStream(),
        headers: {
          'Content-Type': mimeType,
          'Content-Length': fileSize.toString(),
          'Content-Disposition': _encodeContentDisposition(downloadFileName),
          'Cache-Control':
              'public, max-age=3600', // Cache for 1 hour during download
        },
      );
    } catch (e) {
      if (releaseOnError) {
        _releaseDownloadSlot(userKey);
      }
      print(
          '[HttpServer] Download failed userId=$userKey songId=$path error=$e');
      if (e is FileSystemException) {
        return _retryableErrorResponse(
          statusCode: 503,
          error: 'Server busy',
          message: 'File system error during download, try again',
        );
      }
      return Response.internalServerError(
        body: jsonEncode({
          'error': 'Download failed',
          'message': 'Unexpected server error during download',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Encodes a filename for Content-Disposition header (RFC 5987)
  /// Provides ASCII-safe fallback and UTF-8 encoded filename for proper
  /// handling of non-ASCII characters (accents, Korean, Chinese, etc.)
  String _encodeContentDisposition(String filename) {
    // ASCII-safe fallback: replace non-ASCII chars with underscore
    final asciiFallback = filename.runes
        .map((r) => r < 128 ? String.fromCharCode(r) : '_')
        .join()
        .replaceAll('"', "'");

    // RFC 5987 percent-encode the UTF-8 filename
    final utf8Encoded = Uri.encodeComponent(filename);

    return 'attachment; filename="$asciiFallback"; filename*=UTF-8\'\'$utf8Encoded';
  }

  void _releaseDownloadSlot(String userId) {
    _downloadLimiter.release(userId);
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

  /// Handle WebSocket connection
  void _handleWebSocket(dynamic webSocket) {
    print('WebSocket client connected (${_webSocketClients.length + 1} total)');
    _webSocketClients.add(webSocket);

    webSocket.stream.listen(
      (message) {
        _handleWebSocketMessage(webSocket, message);
      },
      onDone: () {
        _webSocketClients.remove(webSocket);
        final deviceId = _webSocketDeviceIds.remove(webSocket);
        if (deviceId != null) {
          _connectionManager.unregisterClient(deviceId);
        } else {
          print(
              'WebSocket disconnected without identify - no client to unregister');
        }
        print(
            'WebSocket client disconnected (${_webSocketClients.length} remaining)');
      },
      onError: (error) {
        _webSocketClients.remove(webSocket);
        final deviceId = _webSocketDeviceIds.remove(webSocket);
        if (deviceId != null) {
          _connectionManager.unregisterClient(deviceId);
        } else {
          print('WebSocket error without identify - no client to unregister');
        }
        print('WebSocket error: $error');
      },
    );
  }

  /// Handle incoming WebSocket message
  void _handleWebSocketMessage(dynamic webSocket, dynamic rawMessage) {
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

        // Validate session token if auth is required
        if (_authRequired && !_legacyMode) {
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

            // Session valid - register client
            if (deviceId.isNotEmpty) {
              _webSocketDeviceIds[webSocket] = deviceId;
              if (!_connectionManager.isClientConnected(deviceId)) {
                _connectionManager.registerClient(
                  deviceId,
                  deviceName ?? 'Unknown Device',
                  userId: session.userId,
                );
              } else {
                _connectionManager.updateHeartbeat(
                  deviceId,
                  userId: session.userId,
                  deviceName: deviceName,
                );
              }
            }
          });
          return;
        }

        // Legacy mode - no auth required
        if (deviceId.isNotEmpty) {
          _webSocketDeviceIds[webSocket] = deviceId;
          if (!_connectionManager.isClientConnected(deviceId)) {
            _connectionManager.registerClient(
              deviceId,
              deviceName ?? 'Unknown Device',
            );
          } else {
            _connectionManager.updateHeartbeat(
              deviceId,
              deviceName: deviceName,
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

      // Other message types can be handled here in future phases
    } catch (e) {
      print('Error parsing WebSocket message: $e');
    }
  }

  /// Send message to a specific WebSocket client
  void _sendWebSocketMessage(dynamic webSocket, WsMessage message) {
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

enum _FairAcquireResult {
  acquired,
  userQuotaExceeded,
  queueFull,
}

class _SimpleLimiter {
  _SimpleLimiter({
    required this.maxConcurrent,
    required this.maxQueue,
  });

  final int maxConcurrent;
  final int maxQueue;
  int _active = 0;
  final Queue<Completer<void>> _queue = Queue<Completer<void>>();

  int get activeCount => _active;
  int get queueLength => _queue.length;
  bool get isIdle => _active == 0 && _queue.isEmpty;

  Future<bool> acquire() async {
    if (_active < maxConcurrent) {
      _active += 1;
      return true;
    }

    if (_queue.length >= maxQueue) {
      return false;
    }

    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
    return true;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final next = _queue.removeFirst();
      if (!next.isCompleted) {
        next.complete();
      }
      return;
    }

    if (_active > 0) {
      _active -= 1;
    }
  }
}

class _WeightedFairDownloadLimiter {
  _WeightedFairDownloadLimiter({
    required this.maxConcurrent,
    required this.maxQueue,
    required this.maxConcurrentPerUser,
    required this.maxQueuePerUser,
  });

  final int maxConcurrent;
  final int maxQueue;
  final int maxConcurrentPerUser;
  final int maxQueuePerUser;

  int _active = 0;
  int _queued = 0;
  final Map<String, _PerUserDownloadQueueState> _states =
      <String, _PerUserDownloadQueueState>{};
  final Queue<String> _rotation = Queue<String>();
  final Map<String, int> _roundCredits = <String, int>{};

  int get activeCount => _active;
  int get queueLength => _queued;
  Map<String, int> get queueDepthByUser {
    final snapshot = <String, int>{};
    _states.forEach((userId, state) {
      if (state.queued > 0) {
        snapshot[userId] = state.queued;
      }
    });
    return snapshot;
  }

  Future<_FairAcquireResult> acquire(String userId) async {
    final state =
        _states.putIfAbsent(userId, () => _PerUserDownloadQueueState());

    final canAcquireImmediately = _queued == 0 &&
        _active < maxConcurrent &&
        state.active < maxConcurrentPerUser;
    if (canAcquireImmediately) {
      _active += 1;
      state.active += 1;
      return _FairAcquireResult.acquired;
    }

    if (state.queued >= maxQueuePerUser) {
      return _FairAcquireResult.userQuotaExceeded;
    }

    if (_queued >= maxQueue) {
      return _FairAcquireResult.queueFull;
    }

    final completer = Completer<void>();
    state.waiters.add(completer);
    state.queued += 1;
    _queued += 1;

    if (!state.inRotation) {
      state.inRotation = true;
      _rotation.addLast(userId);
    }

    await completer.future;
    return _FairAcquireResult.acquired;
  }

  void release(String userId) {
    final state = _states[userId];
    if (state != null && state.active > 0) {
      state.active -= 1;
    }

    if (_active > 0) {
      _active -= 1;
    }

    _grantNextQueuedRequest();
    _cleanupUserState(userId);
  }

  void _grantNextQueuedRequest() {
    if (_active >= maxConcurrent || _rotation.isEmpty) {
      return;
    }

    final usersToCheck = _rotation.length;
    var checked = 0;

    while (checked < usersToCheck && _active < maxConcurrent) {
      final userId = _rotation.removeFirst();
      checked += 1;

      final state = _states[userId];
      if (state == null || state.waiters.isEmpty) {
        if (state != null) {
          state.inRotation = false;
          _cleanupUserState(userId);
        }
        _roundCredits.remove(userId);
        continue;
      }

      if (state.active >= maxConcurrentPerUser) {
        _rotation.addLast(userId);
        continue;
      }

      final weight = 1;
      final availableCredits = _roundCredits[userId] ?? weight;
      final next = state.waiters.removeFirst();
      state.queued -= 1;
      _queued -= 1;
      _active += 1;
      state.active += 1;

      if (!next.isCompleted) {
        next.complete();
      }

      final remainingCredits = availableCredits - 1;
      if (state.waiters.isNotEmpty) {
        if (remainingCredits > 0) {
          _roundCredits[userId] = remainingCredits;
          _rotation.addFirst(userId);
        } else {
          _roundCredits[userId] = weight;
          _rotation.addLast(userId);
        }
      } else {
        state.inRotation = false;
        _roundCredits.remove(userId);
        _cleanupUserState(userId);
      }

      return;
    }
  }

  void _cleanupUserState(String userId) {
    final state = _states[userId];
    if (state == null) return;
    if (state.active == 0 && state.queued == 0 && state.waiters.isEmpty) {
      _states.remove(userId);
      _roundCredits.remove(userId);
    }
  }
}

class _PerUserDownloadQueueState {
  int active = 0;
  int queued = 0;
  bool inRotation = false;
  final Queue<Completer<void>> waiters = Queue<Completer<void>>();
}
