import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:bma_core/services/server/connection_manager.dart';
import 'package:bma_core/services/server/streaming_service.dart';
import 'package:bma_core/models/websocket_models.dart';
import 'package:bma_core/services/library/library_manager.dart';

/// HTTP server for BMA desktop application (Singleton)
class BmaHttpServer {
  // Singleton instance
  static final BmaHttpServer _instance = BmaHttpServer._internal();
  factory BmaHttpServer() => _instance;
  BmaHttpServer._internal();

  HttpServer? _server;
  final ConnectionManager _connectionManager = ConnectionManager();
  final StreamingService _streamingService = StreamingService();
  final LibraryManager _libraryManager = LibraryManager();
  String? _tailscaleIp;  // Kept for backward compatibility
  String? _advertisedIp;  // The IP to show in QR code (Tailscale or LAN IP)
  int _port = 8080;
  final List<dynamic> _webSocketClients = [];

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

  /// Check if server is running
  bool get isRunning => _server != null;

  /// Set the path where web assets are located (for serving web UI)
  void setWebAssetsPath(String path) {
    _webAssetsPath = path;
  }

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
      print('BMA Server already running on http://$_advertisedIp:$_port');
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
        .addMiddleware(_errorMiddleware())
        .addHandler(cascadeHandler);

    try {
      _server = await shelf_io.serve(
        handler,
        bindAddress,
        port,
      );
      print('BMA Server started on http://$bindAddress:$port');
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

    print('BMA Server stopped');
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
            headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Handle Tailscale status request
  Future<Response> _handleTailscaleStatus(Request request) async {
    if (_tailscaleStatusCallback != null) {
      try {
        final status = await _tailscaleStatusCallback!();
        return Response.ok(
          jsonEncode(status),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to get Tailscale status',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
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
            headers: {'Content-Type': 'application/json'},
          );
        }

        final success = await _setMusicFolderCallback!(path);
        return Response.ok(
          jsonEncode({'success': success}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to set music folder',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } else {
      return Response.ok(
        jsonEncode({'success': false, 'message': 'Setup not configured'}),
        headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to start scan',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } else {
      return Response.ok(
        jsonEncode({'success': false, 'message': 'Setup not configured'}),
        headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to get scan status',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to mark setup complete',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } else {
      return Response.ok(
        jsonEncode({'success': false, 'message': 'Setup not configured'}),
        headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Failed to get setup status',
            'message': e.toString(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } else {
      // If no callback configured, assume setup is not complete
      return Response.ok(
        jsonEncode({'isComplete': false}),
        headers: {'Content-Type': 'application/json'},
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
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
      },
    );
  }

  /// Handle get server info request (for QR code generation)
  Response _handleGetServerInfo(Request request) {
    final serverInfo = getServerInfo();
    return Response.ok(
      jsonEncode(serverInfo),
      headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Handle get library request
  Response _handleGetLibrary(Request request) {
    final baseUrl = 'http://${_advertisedIp ?? _tailscaleIp}:$_port';
    final libraryJson = _libraryManager.toApiJson(baseUrl);

    // Debug logging
    print('[HttpServer] Library request - Albums: ${(libraryJson['albums'] as List).length}, Songs: ${(libraryJson['songs'] as List).length}');
    print('[HttpServer] Library manager has library: ${_libraryManager.library != null}');
    print('[HttpServer] Last scan time: ${_libraryManager.lastScanTime}');

    return Response.ok(
      jsonEncode(libraryJson),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Handle get albums request (placeholder for Phase 5)
  Response _handleGetAlbums(Request request) {
    return Response.ok(
      jsonEncode({
        'albums': [],
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Handle get songs request (placeholder for Phase 5)
  Response _handleGetSongs(Request request) {
    return Response.ok(
      jsonEncode({
        'songs': [],
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode(albumDetail),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Handle get album artwork request (lazy extraction with caching)
  Future<Response> _handleGetArtwork(Request request, String albumId) async {
    final artworkData = await _libraryManager.getAlbumArtwork(albumId);

    if (artworkData == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'ARTWORK_NOT_FOUND',
            'message': 'Artwork not found for album: $albumId',
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Return the image data (usually JPEG or PNG)
    return Response.ok(
      artworkData,
      headers: {
        'Content-Type': 'image/jpeg', // Most album art is JPEG
        'Cache-Control': 'public, max-age=31536000', // Cache for 1 year
      },
    );
  }

  /// Handle stream request
  Future<Response> _handleStream(Request request, String path) async {
    // Validate path is provided
    if (path.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': 'Song ID is required',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Look up file path from library by song ID
    final filePath = _libraryManager.getSongFilePath(path);
    if (filePath == null) {
      return Response.notFound(
        jsonEncode({
          'error': 'Song not found',
          'message': 'Song ID not found in library: $path',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final File audioFile = File(filePath);

    // Check if file exists
    if (!await audioFile.exists()) {
      return Response.notFound(
        jsonEncode({
          'error': 'File not found',
          'message': 'Audio file does not exist: $path',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Check if file is in allowed music folder (security check)
    if (_musicFolderPath != null) {
      final canonicalPath = audioFile.absolute.path;
      if (!canonicalPath.startsWith(_musicFolderPath!)) {
        return Response.forbidden(
          jsonEncode({
            'error': 'Forbidden',
            'message': 'File is outside music library',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    // Stream the file
    return await _streamingService.streamFile(audioFile, request);
  }

  /// Handle download request (full file download)
  Future<Response> _handleDownload(Request request, String path) async {
    // Validate path is provided
    if (path.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': 'Song ID is required',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Look up file path from library by song ID
    final filePath = _libraryManager.getSongFilePath(path);
    if (filePath == null) {
      return Response.notFound(
        jsonEncode({
          'error': 'Song not found',
          'message': 'Song ID not found in library: $path',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final File audioFile = File(filePath);

    // Check if file exists
    if (!await audioFile.exists()) {
      return Response.notFound(
        jsonEncode({
          'error': 'File not found',
          'message': 'Audio file does not exist: $path',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Check if file is in allowed music folder (security check)
    if (_musicFolderPath != null) {
      final canonicalPath = audioFile.absolute.path;
      if (!canonicalPath.startsWith(_musicFolderPath!)) {
        return Response.forbidden(
          jsonEncode({
            'error': 'Forbidden',
            'message': 'File is outside music library',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    // Get file size
    final fileSize = await audioFile.length();
    final fileName = audioFile.path.split(Platform.pathSeparator).last;

    // Return the file as a download with appropriate headers
    return Response.ok(
      audioFile.openRead(),
      headers: {
        'Content-Type': 'audio/mpeg', // Assuming MP3 files
        'Content-Length': fileSize.toString(),
        'Content-Disposition': 'attachment; filename="$fileName"',
        'Cache-Control': 'public, max-age=3600', // Cache for 1 hour during download
      },
    );
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
        print('WebSocket client disconnected (${_webSocketClients.length} remaining)');
      },
      onError: (error) {
        _webSocketClients.remove(webSocket);
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
      webSocket.add(jsonString);
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
