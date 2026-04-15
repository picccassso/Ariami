part of '../http_server.dart';

extension AriamiHttpServerMiddlewareAndMetricsMethods on AriamiHttpServer {
  static const String _jsonContentType = 'application/json; charset=utf-8';

  Map<String, String> _jsonHeaders([Map<String, String>? extraHeaders]) {
    if (extraHeaders == null || extraHeaders.isEmpty) {
      return const {'Content-Type': _jsonContentType};
    }
    return {
      'Content-Type': _jsonContentType,
      ...extraHeaders,
    };
  }

  Response _jsonResponse(
    int statusCode,
    Object body, {
    Map<String, String>? headers,
  }) {
    return Response(
      statusCode,
      body: body is String ? body : jsonEncode(body),
      headers: _jsonHeaders(headers),
    );
  }

  Response _jsonOk(
    Object body, {
    Map<String, String>? headers,
  }) {
    return _jsonResponse(HttpStatus.ok, body, headers: headers);
  }

  Response _jsonBadRequest(
    Object body, {
    Map<String, String>? headers,
  }) {
    return _jsonResponse(HttpStatus.badRequest, body, headers: headers);
  }

  Response _jsonUnauthorized(
    Object body, {
    Map<String, String>? headers,
  }) {
    return _jsonResponse(HttpStatus.unauthorized, body, headers: headers);
  }

  Response _jsonForbidden(
    Object body, {
    Map<String, String>? headers,
  }) {
    return _jsonResponse(HttpStatus.forbidden, body, headers: headers);
  }

  Response _jsonNotFound(
    Object body, {
    Map<String, String>? headers,
  }) {
    return _jsonResponse(HttpStatus.notFound, body, headers: headers);
  }

  Response _jsonInternalServerError(
    Object body, {
    Map<String, String>? headers,
  }) {
    return _jsonResponse(
      HttpStatus.internalServerError,
      body,
      headers: headers,
    );
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
    return _jsonUnauthorized({
      'error': {
        'code': AuthErrorCodes.authRequired,
        'message': 'Authentication required',
      },
    });
  }

  Response _forbiddenAdminResponse() {
    return _jsonForbidden({
      'error': {
        'code': AuthErrorCodes.forbiddenAdmin,
        'message': 'Owner privileges required',
      },
    });
  }

  Response _sessionExpiredResponse() {
    return _jsonUnauthorized({
      'error': {
        'code': AuthErrorCodes.sessionExpired,
        'message': 'Session expired or invalid',
      },
    });
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
    return _jsonForbidden({
      'error': {
        'code': AuthErrorCodes.streamTokenExpired,
        'message': message,
      },
    });
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
          return _jsonInternalServerError({
            'error': 'Internal server error',
            'message': e.toString(),
          });
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
}
