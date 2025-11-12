import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../models/server_config.dart';
import '../../models/library_models.dart';
import 'connection_manager.dart';

class HttpServer {
  io.HttpServer? _server;
  final ConnectionManager _connectionManager = ConnectionManager();
  String? _tailscaleIp;
  int? _port;

  // Mock library data (will be replaced with real data in Phase 5)
  final Map<String, Album> _albums = {};
  final Map<String, Song> _songs = {};
  final Map<String, Playlist> _playlists = {};

  // WebSocket connections (sessionId -> WebSocketChannel)
  final Map<String, WebSocketChannel> _webSocketConnections = {};

  Future<bool> start() async {
    try {
      // Get Tailscale IP
      _tailscaleIp = await _getTailscaleIp();
      if (_tailscaleIp == null) {
        print('ERROR: Could not find Tailscale IP address');
        return false;
      }

      print('Starting server on Tailscale IP: $_tailscaleIp:${ServerConfig.port}');

      // Create handler with middleware
      final handler = Pipeline()
          .addMiddleware(_corsMiddleware())
          .addMiddleware(logRequests())
          .addMiddleware(_errorHandlingMiddleware())
          .addMiddleware(_jsonResponseMiddleware())
          .addHandler(_setupRoutes().call);

      // Start server bound to Tailscale interface
      _server = await shelf_io.serve(
        handler,
        _tailscaleIp!,
        ServerConfig.port,
      );

      _port = _server!.port;
      print('Server started successfully on http://$_tailscaleIp:$_port');
      print('API Version: ${ServerConfig.apiVersion}');
      print('Max Connections: ${ServerConfig.maxConnections}');

      return true;
    } catch (e) {
      print('ERROR: Failed to start server: $e');
      return false;
    }
  }

  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _connectionManager.dispose();
      print('Server stopped');
    }
  }

  Router _setupRoutes() {
    final router = Router();

    // Connection endpoints
    router.get('/api/ping', _pingHandler);
    router.post('/api/connect', _connectHandler);
    router.post('/api/disconnect', _disconnectHandler);

    // Library endpoints (placeholders for Task 4.2)
    router.get('/api/library', _getLibraryHandler);
    router.get('/api/albums/<id>', _getAlbumHandler);
    router.get('/api/songs/<id>', _getSongHandler);

    // Streaming endpoint (placeholder for Task 4.2)
    router.get('/api/stream/<id>', _streamSongHandler);

    // Artwork endpoint (placeholder for Task 4.2)
    router.get('/api/artwork/<id>', _getArtworkHandler);

    // WebSocket endpoint (placeholder for Task 4.4)
    router.get('/ws', _webSocketHandler);

    // Catch-all for undefined routes
    router.all('/<ignored|.*>', (Request request) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'ROUTE_NOT_FOUND',
            'message': 'The requested endpoint does not exist',
          }
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    return router;
  }

  // ===== MIDDLEWARE =====

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _getCorsHeaders());
        }

        final response = await handler(request);
        return response.change(headers: _getCorsHeaders());
      };
    };
  }

  Map<String, String> _getCorsHeaders() {
    return {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };
  }

  Middleware _errorHandlingMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        try {
          return await handler(request);
        } catch (e, stackTrace) {
          print('ERROR: $e');
          print('Stack trace: $stackTrace');
          return Response.internalServerError(
            body: jsonEncode({
              'error': {
                'code': 'SERVER_ERROR',
                'message': 'An internal server error occurred',
                'details': {},
              }
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      };
    };
  }

  Middleware _jsonResponseMiddleware() {
    return createMiddleware(
      responseHandler: (Response response) {
        if (!response.headers.containsKey('Content-Type')) {
          return response.change(headers: {'Content-Type': 'application/json'});
        }
        return response;
      },
    );
  }

  // ===== ROUTE HANDLERS =====

  Response _pingHandler(Request request) {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'timestamp': DateTime.now().toIso8601String(),
        'version': ServerConfig.apiVersion,
      }),
    );
  }

  Future<Response> _connectHandler(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());

      // Validate required fields
      if (payload['deviceId'] == null ||
          payload['deviceName'] == null ||
          payload['appVersion'] == null ||
          payload['platform'] == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'Missing required fields',
            }
          }),
        );
      }

      // Check max connections
      if (_connectionManager.clientCount >= ServerConfig.maxConnections) {
        return Response(503,
            body: jsonEncode({
              'error': {
                'code': 'MAX_CONNECTIONS',
                'message': 'Server has reached maximum connection limit',
              }
            }));
      }

      // Add client
      final sessionId = _connectionManager.addClient(
        deviceId: payload['deviceId'],
        deviceName: payload['deviceName'],
        platform: payload['platform'],
      );

      return Response.ok(
        jsonEncode({
          'status': 'connected',
          'sessionId': sessionId,
          'serverVersion': ServerConfig.apiVersion,
          'features': ['streaming', 'offline', 'playlists'],
        }),
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'Invalid request body',
          }
        }),
      );
    }
  }

  Future<Response> _disconnectHandler(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());

      if (payload['sessionId'] == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'Missing sessionId',
            }
          }),
        );
      }

      final removed = _connectionManager.removeClient(payload['sessionId']);

      if (!removed) {
        return Response.notFound(
          jsonEncode({
            'error': {
              'code': 'INVALID_SESSION',
              'message': 'Session not found',
            }
          }),
        );
      }

      return Response.ok(
        jsonEncode({'status': 'disconnected'}),
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'Invalid request body',
          }
        }),
      );
    }
  }

  // Library endpoint handlers
  Response _getLibraryHandler(Request request) {
    final library = Library(
      albums: _albums.values.toList(),
      songs: _songs.values.toList(),
      playlists: _playlists.values.toList(),
      lastUpdated: DateTime.now(),
    );

    return Response.ok(jsonEncode(library.toJson()));
  }

  Response _getAlbumHandler(Request request, String id) {
    final album = _albums[id];

    if (album == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'ALBUM_NOT_FOUND',
            'message': 'Album with id "$id" not found',
            'details': {},
          }
        }),
      );
    }

    return Response.ok(jsonEncode(album.toJson(includeSongs: true)));
  }

  Response _getSongHandler(Request request, String id) {
    final song = _songs[id];

    if (song == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'SONG_NOT_FOUND',
            'message': 'Song with id "$id" not found',
            'details': {},
          }
        }),
      );
    }

    return Response.ok(jsonEncode(song.toJson()));
  }

  Future<Response> _streamSongHandler(Request request, String id) async {
    final song = _songs[id];

    if (song == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'SONG_NOT_FOUND',
            'message': 'Song with id "$id" not found',
            'details': {},
          }
        }),
      );
    }

    if (song.filePath == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'FILE_NOT_FOUND',
            'message': 'Audio file path not available',
            'details': {},
          }
        }),
      );
    }

    final file = io.File(song.filePath!);
    if (!await file.exists()) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'FILE_NOT_FOUND',
            'message': 'Audio file does not exist',
            'details': {},
          }
        }),
      );
    }

    // Get file stats
    final fileStats = await file.stat();
    final fileSize = fileStats.size;

    // Parse Range header for seeking support
    final rangeHeader = request.headers['range'];
    int start = 0;
    int end = fileSize - 1;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final range = rangeHeader.substring(6).split('-');
      start = int.tryParse(range[0]) ?? 0;
      if (range.length > 1 && range[1].isNotEmpty) {
        end = int.tryParse(range[1]) ?? end;
      }
    }

    // Validate range
    if (start >= fileSize || end >= fileSize || start > end) {
      return Response(416, // Range Not Satisfiable
          body: jsonEncode({
            'error': {
              'code': 'INVALID_RANGE',
              'message': 'Requested range not satisfiable',
              'details': {},
            }
          }));
    }

    final length = end - start + 1;

    // Read file segment
    final randomAccessFile = await file.open(mode: io.FileMode.read);
    await randomAccessFile.setPosition(start);
    final bytes = await randomAccessFile.read(length);
    await randomAccessFile.close();

    // Determine content type
    String contentType = 'audio/mpeg'; // default
    if (song.filePath!.endsWith('.mp3')) {
      contentType = 'audio/mpeg';
    } else if (song.filePath!.endsWith('.m4a') || song.filePath!.endsWith('.aac')) {
      contentType = 'audio/aac';
    } else if (song.filePath!.endsWith('.flac')) {
      contentType = 'audio/flac';
    } else if (song.filePath!.endsWith('.wav')) {
      contentType = 'audio/wav';
    }

    final headers = {
      'Content-Type': contentType,
      'Content-Length': length.toString(),
      'Accept-Ranges': 'bytes',
    };

    if (rangeHeader != null) {
      headers['Content-Range'] = 'bytes $start-$end/$fileSize';
      return Response(206, body: bytes, headers: headers); // Partial Content
    }

    return Response.ok(bytes, headers: headers);
  }

  Future<Response> _getArtworkHandler(Request request, String id) async {
    final album = _albums[id];

    if (album == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'ALBUM_NOT_FOUND',
            'message': 'Album with id "$id" not found',
            'details': {},
          }
        }),
      );
    }

    if (album.coverArtPath == null) {
      // Return a placeholder or 404
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'ARTWORK_NOT_FOUND',
            'message': 'Album artwork not available',
            'details': {},
          }
        }),
      );
    }

    final file = io.File(album.coverArtPath!);
    if (!await file.exists()) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'FILE_NOT_FOUND',
            'message': 'Artwork file does not exist',
            'details': {},
          }
        }),
      );
    }

    final bytes = await file.readAsBytes();

    // Determine content type based on file extension
    String contentType = 'image/jpeg'; // default
    if (album.coverArtPath!.endsWith('.png')) {
      contentType = 'image/png';
    } else if (album.coverArtPath!.endsWith('.jpg') || album.coverArtPath!.endsWith('.jpeg')) {
      contentType = 'image/jpeg';
    } else if (album.coverArtPath!.endsWith('.webp')) {
      contentType = 'image/webp';
    }

    return Response.ok(
      bytes,
      headers: {
        'Content-Type': contentType,
        'Content-Length': bytes.length.toString(),
        'Cache-Control': 'public, max-age=86400', // Cache for 24 hours
      },
    );
  }

  Future<Response> _webSocketHandler(Request request) async {
    // Get session ID from query parameter
    final sessionId = request.url.queryParameters['session'];

    if (sessionId == null || sessionId.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'Missing session parameter',
          }
        }),
      );
    }

    // Verify session exists
    if (!_connectionManager.isValidSession(sessionId)) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'INVALID_SESSION',
            'message': 'Session not found',
          }
        }),
      );
    }

    // Upgrade to WebSocket
    return webSocketHandler((WebSocketChannel webSocket) {
      print('WebSocket client connected: $sessionId');

      // Store WebSocket channel
      _webSocketConnections[sessionId] = webSocket;

      // Listen for messages from client
      webSocket.stream.listen(
        (message) {
          _handleWebSocketMessage(sessionId, message);
        },
        onDone: () {
          print('WebSocket client disconnected: $sessionId');
          _webSocketConnections.remove(sessionId);
        },
        onError: (error) {
          print('WebSocket error for $sessionId: $error');
          _webSocketConnections.remove(sessionId);
        },
        cancelOnError: true,
      );

      // Send welcome message
      _sendWebSocketMessage(sessionId, {
        'type': 'server_notification',
        'data': {
          'severity': 'info',
          'message': 'WebSocket connection established',
        }
      });
    })(request);
  }

  /// Handle incoming WebSocket message from client
  void _handleWebSocketMessage(String sessionId, dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final type = data['type'] as String?;

      print('WebSocket message from $sessionId: $type');

      // Handle different message types
      switch (type) {
        case 'now_playing':
          // Broadcast to other clients (future enhancement)
          _broadcastToOtherClients(sessionId, data);
          break;
        default:
          print('Unknown WebSocket message type: $type');
      }
    } catch (e) {
      print('Error handling WebSocket message: $e');
    }
  }

  /// Send a message to a specific WebSocket client
  void _sendWebSocketMessage(String sessionId, Map<String, dynamic> message) {
    final channel = _webSocketConnections[sessionId];
    if (channel != null) {
      try {
        channel.sink.add(jsonEncode(message));
      } catch (e) {
        print('Error sending WebSocket message to $sessionId: $e');
      }
    }
  }

  /// Broadcast a message to all connected WebSocket clients
  void _broadcastWebSocketMessage(Map<String, dynamic> message) {
    final jsonMessage = jsonEncode(message);
    for (final entry in _webSocketConnections.entries) {
      try {
        entry.value.sink.add(jsonMessage);
      } catch (e) {
        print('Error broadcasting to ${entry.key}: $e');
      }
    }
  }

  /// Broadcast to all clients except the sender
  void _broadcastToOtherClients(
      String senderSessionId, Map<String, dynamic> message) {
    final jsonMessage = jsonEncode(message);
    for (final entry in _webSocketConnections.entries) {
      if (entry.key != senderSessionId) {
        try {
          entry.value.sink.add(jsonMessage);
        } catch (e) {
          print('Error broadcasting to ${entry.key}: $e');
        }
      }
    }
  }

  // ===== PUBLIC BROADCAST METHODS =====

  /// Broadcast library update to all clients
  void broadcastLibraryUpdate({
    required String updateType,
    required List<String> affectedIds,
  }) {
    _broadcastWebSocketMessage({
      'type': 'library_update',
      'data': {
        'updateType': updateType,
        'affectedIds': affectedIds,
        'timestamp': DateTime.now().toIso8601String(),
      }
    });
    print(
        'Broadcasted library update: $updateType (${affectedIds.length} items)');
  }

  /// Broadcast server notification to all clients
  void broadcastNotification({
    required String severity,
    required String message,
  }) {
    _broadcastWebSocketMessage({
      'type': 'server_notification',
      'data': {
        'severity': severity,
        'message': message,
      }
    });
    print('Broadcasted notification [$severity]: $message');
  }

  // ===== UTILITY METHODS =====

  Future<String?> _getTailscaleIp() async {
    try {
      // Try to get Tailscale IP from network interfaces
      final interfaces = await io.NetworkInterface.list();

      for (var interface in interfaces) {
        // Tailscale interface is typically named "utun" on macOS or "tailscale0" on Linux
        if (interface.name.contains('utun') ||
            interface.name.contains('tailscale')) {
          for (var addr in interface.addresses) {
            if (addr.type == io.InternetAddressType.IPv4) {
              // Tailscale IPs are in the 100.x.x.x range
              if (addr.address.startsWith('100.')) {
                return addr.address;
              }
            }
          }
        }
      }

      // Fallback: try to find any IP in the Tailscale range
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == io.InternetAddressType.IPv4 &&
              addr.address.startsWith('100.')) {
            return addr.address;
          }
        }
      }

      return null;
    } catch (e) {
      print('ERROR: Failed to get Tailscale IP: $e');
      return null;
    }
  }

  String? get tailscaleIp => _tailscaleIp;
  int? get port => _port;
  ConnectionManager get connectionManager => _connectionManager;
}
