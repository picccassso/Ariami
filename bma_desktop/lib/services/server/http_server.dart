import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'connection_manager.dart';
import 'streaming_service.dart';
import '../../models/websocket_models.dart';

/// HTTP server for BMA desktop application (Singleton)
class BmaHttpServer {
  // Singleton instance
  static final BmaHttpServer _instance = BmaHttpServer._internal();
  factory BmaHttpServer() => _instance;
  BmaHttpServer._internal();

  HttpServer? _server;
  final ConnectionManager _connectionManager = ConnectionManager();
  final StreamingService _streamingService = StreamingService();
  String? _tailscaleIp;
  int _port = 8080;
  final List<dynamic> _webSocketClients = [];

  // Store music folder path (set from desktop state)
  String? _musicFolderPath;

  /// Check if server is running
  bool get isRunning => _server != null;

  /// Start the HTTP server on Tailscale interface
  Future<void> start({required String tailscaleIp, int port = 8080}) async {
    // If already running, don't start again
    if (_server != null) {
      print('BMA Server already running on http://$_tailscaleIp:$_port');
      return;
    }
    _tailscaleIp = tailscaleIp;
    _port = port;

    final router = _buildRouter();
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_errorMiddleware())
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(
        handler,
        tailscaleIp,
        port,
      );
      print('BMA Server started on http://$tailscaleIp:$port');

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
      'server': _tailscaleIp,
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

    // Connection management
    router.post('/api/connect', _handleConnect);
    router.post('/api/disconnect', _handleDisconnect);

    // Library endpoints
    router.get('/api/library', _handleGetLibrary);
    router.get('/api/albums', _handleGetAlbums);
    router.get('/api/songs', _handleGetSongs);

    // Streaming endpoint - captures everything after /api/stream/
    router.get('/api/stream/<path|.*>', _handleStream);

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
  Response _handlePing(Request request) {
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

      _connectionManager.unregisterClient(deviceId);

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

  /// Handle get library request (placeholder for Phase 5)
  Response _handleGetLibrary(Request request) {
    return Response.ok(
      jsonEncode({
        'albums': [],
        'totalSongs': 0,
        'timestamp': DateTime.now().toIso8601String(),
      }),
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

  /// Handle stream request
  Future<Response> _handleStream(Request request, String path) async {
    // Validate path is provided
    if (path.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': 'File path is required',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // For now, treat path parameter as file path
    // In future phases, this will look up the file path from database by song ID
    final File audioFile = File(path);

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
        _connectionManager.cleanupStaleConnections();
        _startCleanupTimer();
      }
    });
  }

  /// Get connection manager
  ConnectionManager get connectionManager => _connectionManager;
}
