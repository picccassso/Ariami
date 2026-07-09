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
  Middleware _authRateLimitMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final path = '/${request.url.path}';
        if (path != '/api/auth/login' && path != '/api/auth/register') {
          return await handler(request);
        }

        final key = '$path|${_clientIp(request)}';
        final tracker = _authEndpointAttempts.putIfAbsent(
          key,
          () => _AuthEndpointRateLimitTracker(),
        );
        if (tracker.isLocked) {
          final remainingMinutes =
              (tracker.remainingLockTime.inSeconds / 60).ceil();
          return _jsonResponse(HttpStatus.tooManyRequests, {
            'error': {
              'code': AuthErrorCodes.rateLimited,
              'message':
                  'Too many failed auth attempts. Try again in $remainingMinutes minute${remainingMinutes == 1 ? '' : 's'}.',
            },
          });
        }

        final response = await handler(request);
        if (response.statusCode == HttpStatus.ok ||
            response.statusCode == HttpStatus.created) {
          tracker.reset();
        } else if (response.statusCode == HttpStatus.badRequest ||
            response.statusCode == HttpStatus.unauthorized ||
            // Registration with a bad/expired invite code answers 403; count
            // it, or invite codes could be brute-forced without tripping the
            // limiter.
            response.statusCode == HttpStatus.forbidden ||
            response.statusCode == HttpStatus.conflict) {
          tracker.recordFailure(
            AuthService.maxLoginAttempts,
            AuthService.rateLimitCooldown,
          );
        }
        return response;
      };
    };
  }

  String _clientIp(Request request) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.trim().isNotEmpty) {
      return forwarded.split(',').first.trim();
    }

    final connectionInfo = request.context['shelf.io.connection_info'];
    if (connectionInfo is HttpConnectionInfo) {
      return connectionInfo.remoteAddress.address;
    }

    final ioRequest = request.context['shelf.io.request'];
    if (ioRequest is HttpRequest) {
      return ioRequest.connectionInfo?.remoteAddress.address ?? 'unknown_ip';
    }

    return 'unknown_ip';
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

        final hasUsers = _hasRegisteredUsers();

        // Public endpoints that don't require authentication.
        //
        // First-run bootstrap keeps setup and initial registration reachable,
        // but legacy mode must not open the full library/API surface.
        final isBootstrapAuthPath = !hasUsers &&
            (path == '/api/auth/login' || path == '/api/auth/register');
        final isBootstrapSetupPath =
            !hasUsers && path.startsWith('/api/setup/');
        // Playlist-suggestion decisions are setup-grade library actions; the
        // handlers enforce admin once users exist (_authorizeSetupRequest).
        final isBootstrapSuggestionsPath =
            !hasUsers && path.startsWith('/api/playlists/suggestions');
        final isMediaTicketPath = hasUsers &&
            (path == '/api/stream' ||
                path.startsWith('/api/stream/') ||
                path == '/api/download' ||
                path.startsWith('/api/download/'));
        final isPublicPath = path == '/api/ping' ||
            path == '/api/server-info' ||
            path == '/api/setup/status' ||
            path == '/api/ws' ||
            path == '/api/auth/login' ||
            path == '/api/auth/register' ||
            path == '/api/auth/users' ||
            path.startsWith('/api/auth/user-avatar/') ||
            path.startsWith('/api/tailscale/') ||
            isBootstrapAuthPath ||
            isBootstrapSetupPath ||
            isBootstrapSuggestionsPath ||
            isMediaTicketPath;

        if (isPublicPath) {
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

  bool _hasRegisteredUsers() {
    try {
      return _authService.hasUsers();
    } on StateError {
      return false;
    }
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
    if (!_hasRegisteredUsers()) {
      return _authRequiredResponse();
    }

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
    if (!_hasRegisteredUsers()) {
      return _authRequiredResponse();
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
            // The reported name would silently undo a user rename here.
            deviceName: _customOrReportedDeviceName(deviceId, deviceName),
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
    if (path.startsWith('/api/auth/user-avatar/')) {
      return '/api/auth/user-avatar/:username';
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

class _AuthEndpointRateLimitTracker {
  int failedAttempts = 0;
  DateTime? lockedUntil;

  bool get isLocked {
    if (lockedUntil == null) return false;
    if (DateTime.now().isAfter(lockedUntil!)) {
      reset();
      return false;
    }
    return true;
  }

  Duration get remainingLockTime {
    if (lockedUntil == null) return Duration.zero;
    final remaining = lockedUntil!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void recordFailure(int maxAttempts, Duration cooldown) {
    failedAttempts++;
    if (failedAttempts >= maxAttempts) {
      lockedUntil = DateTime.now().add(cooldown);
    }
  }

  void reset() {
    failedAttempts = 0;
    lockedUntil = null;
  }
}
