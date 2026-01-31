import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:ariami_core/services/server/connection_manager.dart';
import 'package:ariami_core/services/server/streaming_service.dart';
import 'package:ariami_core/services/transcoding/transcoding_service.dart';
import 'package:ariami_core/services/artwork/artwork_service.dart';
import 'package:ariami_core/models/quality_preset.dart';
import 'package:ariami_core/models/artwork_size.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/library/library_manager.dart';

/// HTTP server for Ariami desktop application (Singleton)
class AriamiHttpServer {
  // Singleton instance
  static final AriamiHttpServer _instance = AriamiHttpServer._internal();
  factory AriamiHttpServer() => _instance;
  AriamiHttpServer._internal();

  HttpServer? _server;
  final ConnectionManager _connectionManager = ConnectionManager();
  final StreamingService _streamingService = StreamingService();
  final LibraryManager _libraryManager = LibraryManager();
  TranscodingService? _transcodingService;
  ArtworkService? _artworkService;
  String? _tailscaleIp;  // Kept for backward compatibility
  String? _advertisedIp;  // The IP to show in QR code (Tailscale or LAN IP)
  int _port = 8080;
  final List<dynamic> _webSocketClients = [];
  final Map<dynamic, String> _webSocketDeviceIds = {};

  // Store music folder path (set from desktop state)
  String? _musicFolderPath;

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
  void setTailscaleStatusCallback(Future<Map<String, dynamic>> Function() callback) {
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
  void setTransitionToBackgroundCallback(Future<Map<String, dynamic>> Function() callback) {
    _transitionToBackgroundCallback = callback;
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
      _tailscaleIp = advertisedIp;  // Backward compatibility
      _port = port;
      print('Ariami Server already running on http://$_advertisedIp:$_port');
      return;
    }
    _advertisedIp = advertisedIp;
    _tailscaleIp = advertisedIp;  // Backward compatibility
    _port = port;

    final router = _buildRouter();

    // Build handler with Cascade to support both API and static files
    final Handler cascadeHandler = Cascade()
        .add(router.call)  // API routes have priority
        .add(_webAssetsPath != null ? _createStaticHandler() : _notFoundHandler())
        .handler;

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_connectionTrackingMiddleware())
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

      // Start cleanup timer for stale connections
      _startCleanupTimer();
    } catch (e) {
      print('Failed to start server: $e');
      rethrow;
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

    print('Ariami Server stopped');
  }

  /// Get server info for QR code generation
  Map<String, dynamic> getServerInfo() {
    return {
      'server': _advertisedIp ?? _tailscaleIp,
      'port': _port,
      'name': Platform.localHostname,
      'version': '1.0.0',
    };
  }

  /// Build the router with all API routes
  Router _buildRouter() {
    final router = Router();

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
    router.post('/api/setup/transition-to-background', _handleTransitionToBackground);

    // Stats endpoint (for dashboard)
    router.get('/api/stats', _handleGetStats);

    // Server info endpoint (for QR code generation)
    router.get('/api/server-info', _handleGetServerInfo);

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

  /// Middleware to track active clients via deviceId/deviceName on any request
  Middleware _connectionTrackingMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final deviceId = request.url.queryParameters['deviceId'];
        if (deviceId != null && deviceId.isNotEmpty) {
          final deviceName = request.url.queryParameters['deviceName'];
          if (_connectionManager.isClientConnected(deviceId)) {
            _connectionManager.updateHeartbeat(deviceId);
          } else {
            _connectionManager.registerClient(
              deviceId,
              (deviceName != null && deviceName.isNotEmpty)
                  ? deviceName
                  : 'Unknown Device',
            );
          }
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

  /// Handle ping request
  /// Optionally accepts deviceId query parameter to update heartbeat
  Response _handlePing(Request request) {
    // Update heartbeat if deviceId is provided
    final deviceId = request.url.queryParameters['deviceId'];
    if (deviceId != null && deviceId.isNotEmpty) {
      _connectionManager.updateHeartbeat(deviceId);
    }

    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'timestamp': DateTime.now().toIso8601String(),
        'server': Platform.localHostname,
        'version': '1.0.0',
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

  /// Handle client connection
  Future<Response> _handleConnect(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final deviceId = data['deviceId'] as String?;
      final deviceName = data['deviceName'] as String?;

      if (deviceId == null || deviceName == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing required fields',
            'message': 'deviceId and deviceName are required',
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      _connectionManager.registerClient(deviceId, deviceName);

      // Broadcast client connection to all WebSocket clients
      broadcastWebSocketMessage(ClientConnectedMessage(
        clientCount: _connectionManager.clientCount,
        deviceName: deviceName,
      ));

      // Generate session ID
      final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}_$deviceId';

      return Response.ok(
        jsonEncode({
          'status': 'connected',
          'sessionId': sessionId,
          'serverVersion': '1.0.0',
          'features': ['library', 'streaming', 'websocket'],
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

  /// Handle client disconnection
  Future<Response> _handleDisconnect(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final deviceId = data['deviceId'] as String?;

      if (deviceId == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing required field',
            'message': 'deviceId is required',
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // Get client name before unregistering
      final client = _connectionManager.getClient(deviceId);
      _connectionManager.unregisterClient(deviceId);

      // Broadcast client disconnection to all WebSocket clients
      broadcastWebSocketMessage(ClientDisconnectedMessage(
        clientCount: _connectionManager.clientCount,
        deviceName: client?.deviceName,
      ));

      return Response.ok(
        jsonEncode({
          'status': 'disconnected',
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

  /// Handle get library request
  Future<Response> _handleGetLibrary(Request request) async {
    final baseUrl = 'http://${_advertisedIp ?? _tailscaleIp}:$_port';
    final libraryJson = await _libraryManager.toApiJsonWithDurations(baseUrl);

    // Debug logging
    print('[HttpServer] Library request - Albums: ${(libraryJson['albums'] as List).length}, Songs: ${(libraryJson['songs'] as List).length}');
    print('[HttpServer] Library manager has library: ${_libraryManager.library != null}');
    print('[HttpServer] Last scan time: ${_libraryManager.lastScanTime}');

    return Response.ok(
      jsonEncode(libraryJson),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
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

  /// Handle get album detail request
  Future<Response> _handleGetAlbumDetail(Request request, String albumId) async {
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

    // Process artwork if size requested and service available
    List<int> responseData = artworkData;
    if (size.requiresProcessing && _artworkService != null) {
      responseData = await _artworkService!.getArtwork(albumId, artworkData, size);
      print('[HttpServer] Serving ${size.name} artwork for album $albumId (${responseData.length} bytes)');
    }

    // Return the image data (usually JPEG or PNG)
    return Response.ok(
      responseData,
      headers: {
        'Content-Type': 'image/jpeg', // Most album art is JPEG
        'Cache-Control': 'public, max-age=31536000', // Cache for 1 year
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

    // Process artwork if size requested and service available
    // Use songId as the cache key for song artwork
    List<int> responseData = artworkData;
    if (size.requiresProcessing && _artworkService != null) {
      responseData = await _artworkService!.getArtwork('song_$songId', artworkData, size);
      print('[HttpServer] Serving ${size.name} artwork for song $songId (${responseData.length} bytes)');
    }

    // Return the image data (usually JPEG or PNG)
    return Response.ok(
      responseData,
      headers: {
        'Content-Type': 'image/jpeg', // Most album art is JPEG
        'Cache-Control': 'public, max-age=31536000', // Cache for 1 year
        'X-Artwork-Size': size.name, // Debug header
      },
    );
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
        print('[HttpServer] Streaming transcode started for $path at ${quality.name}');
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
        print('[HttpServer] Streaming transcoded file at ${quality.name} quality');

        // Stream the file and release in-use when done
        try {
          return await _streamingService.streamFile(fileToStream, request);
        } finally {
          _transcodingService!.releaseInUse(path, quality);
        }
      } else {
        // Transcoding failed or FFmpeg not available - fall back to original
        print('[HttpServer] Transcoding unavailable, falling back to original file');
      }
    } else if (quality.requiresTranscoding && _transcodingService == null) {
      print('[HttpServer] Transcoding requested but service not configured, using original');
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

    // Determine which file to download
    File fileToDownload = originalFile;
    String mimeType = _streamingService.getAudioMimeType(originalFile.path);
    DownloadTranscodeResult? downloadTranscodeResult;

    // If transcoding is requested and service is available
    if (quality.requiresTranscoding && _transcodingService != null) {
      // Use dedicated download pipeline (temp file, not cached)
      // This prevents cache churn during bulk downloads
      downloadTranscodeResult = await _transcodingService!.getDownloadTranscode(
        filePath,
        path, // songId
        quality,
      );

      if (downloadTranscodeResult != null) {
        fileToDownload = downloadTranscodeResult.tempFile;
        mimeType = quality.mimeType ?? mimeType;
        print('[HttpServer] Downloading transcoded file at ${quality.name} quality (temp file)');
      } else {
        // Transcoding failed or FFmpeg not available - fall back to original
        print('[HttpServer] Transcoding unavailable for download, falling back to original file');
      }
    } else if (quality.requiresTranscoding && _transcodingService == null) {
      print('[HttpServer] Transcoding requested for download but service not configured, using original');
    }

    // Get file info
    final fileSize = await fileToDownload.length();
    final originalFileName = originalFile.path.split(Platform.pathSeparator).last;

    // Adjust filename extension if transcoded
    String downloadFileName = originalFileName;
    if (downloadTranscodeResult != null && quality.fileExtension != null) {
      // Replace extension with transcoded format extension
      final lastDot = originalFileName.lastIndexOf('.');
      if (lastDot > 0) {
        downloadFileName = '${originalFileName.substring(0, lastDot)}.${quality.fileExtension}';
      } else {
        downloadFileName = '$originalFileName.${quality.fileExtension}';
      }
    }

    // Open file with explicit handle management to prevent file handle leaks
    final RandomAccessFile raf = await fileToDownload.open(mode: FileMode.read);

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
      }
    }

    // Return the file as a download with appropriate headers
    return Response.ok(
      createFileStream(),
      headers: {
        'Content-Type': mimeType,
        'Content-Length': fileSize.toString(),
        'Content-Disposition': _encodeContentDisposition(downloadFileName),
        'Cache-Control': 'public, max-age=3600', // Cache for 1 hour during download
      },
    );
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

  /// Set music folder path for security validation
  void setMusicFolderPath(String path) {
    _musicFolderPath = path;
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
          print('WebSocket disconnected without identify - no client to unregister');
        }
        print('WebSocket client disconnected (${_webSocketClients.length} remaining)');
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
      final jsonMessage = jsonDecode(rawMessage as String) as Map<String, dynamic>;
      final message = WsMessage.fromJson(jsonMessage);

      print('WebSocket message received: ${message.type}');

      // Handle identify
      if (message.type == WsMessageType.identify) {
        final deviceId = message.data?['deviceId'] as String?;
        final deviceName = message.data?['deviceName'] as String?;
        if (deviceId != null && deviceId.isNotEmpty) {
          _webSocketDeviceIds[webSocket] = deviceId;
          if (!_connectionManager.isClientConnected(deviceId)) {
            _connectionManager.registerClient(
              deviceId,
              deviceName ?? 'Unknown Device',
            );
          }
        }
        return;
      }

      // Handle ping
      if (message.type == WsMessageType.ping) {
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
    print('Broadcasting ${message.type} to ${_webSocketClients.length} clients');
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
}
