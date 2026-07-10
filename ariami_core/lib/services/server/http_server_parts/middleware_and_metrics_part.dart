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

  /// CORS middleware.
  ///
  /// The dashboards Ariami serves are same-origin, and the native clients
  /// don't send an Origin header, so no legitimate caller needs a wildcard.
  /// Cross-origin access is only granted to the server's own origins
  /// (matching the request Host) and to loopback origins for local
  /// development of the web dashboard.
  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final corsHeaders = _corsHeadersForRequest(request);
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: corsHeaders);
        }

        final response = await handler(request);
        return response.change(headers: corsHeaders);
      };
    };
  }

  Map<String, String> _corsHeadersForRequest(Request request) {
    final origin = request.headers['origin'];
    if (origin == null || origin.isEmpty) {
      return const {};
    }
    if (!_isAllowedCorsOrigin(origin, request.headers['host'])) {
      return const {'Vary': 'Origin'};
    }
    return {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Vary': 'Origin',
    };
  }

  bool _isAllowedCorsOrigin(String origin, String? hostHeader) {
    final Uri originUri;
    try {
      originUri = Uri.parse(origin);
    } on FormatException {
      return false;
    }
    if (originUri.host.isEmpty) {
      return false;
    }

    final originHost = originUri.host.toLowerCase();
    // Loopback origins keep local dashboard development working.
    if (originHost == 'localhost' ||
        originHost == '127.0.0.1' ||
        originHost == '::1' ||
        originHost == '[::1]') {
      return true;
    }

    // Same host:port as the request target = the dashboard this server
    // itself serves (over any of its addresses).
    if (hostHeader == null || hostHeader.isEmpty) {
      return false;
    }
    final originPort = originUri.hasPort ? originUri.port : null;
    final hostParts = hostHeader.toLowerCase().split(':');
    final requestHost = hostParts.first;
    final requestPort =
        hostParts.length > 1 ? int.tryParse(hostParts.last) : null;
    return originHost == requestHost &&
        (originPort ?? _port) == (requestPort ?? _port);
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
        _pruneAuthEndpointAttempts();
        final tracker = _authEndpointAttempts.putIfAbsent(
          key,
          () => _AuthEndpointRateLimitTracker(),
        );
        tracker.touch();
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

  /// Evict stale/expired auth rate-limit trackers so the map stays bounded.
  /// Entries idle longer than the cooldown carry no rate-limit state worth
  /// keeping; if the map is still oversized (an attacker rotating spoofable
  /// keys), the least recently touched entries are dropped first.
  void _pruneAuthEndpointAttempts() {
    const maxEntries = 5000;
    final now = DateTime.now();
    _authEndpointAttempts.removeWhere((_, tracker) =>
        !tracker.isLocked &&
        now.difference(tracker.lastAttemptAt) > AuthService.rateLimitCooldown);

    if (_authEndpointAttempts.length < maxEntries) {
      return;
    }
    final keysByAge = _authEndpointAttempts.keys.toList()
      ..sort((a, b) => _authEndpointAttempts[a]!
          .lastAttemptAt
          .compareTo(_authEndpointAttempts[b]!.lastAttemptAt));
    for (final key
        in keysByAge.take(_authEndpointAttempts.length - maxEntries + 1)) {
      _authEndpointAttempts.remove(key);
    }
  }

  String _clientIp(Request request) {
    // X-Forwarded-For is client-controlled; only honor it when the owner has
    // explicitly said Ariami sits behind a proxy they trust.
    if (_trustProxyHeaders) {
      final forwarded = request.headers['x-forwarded-for'];
      if (forwarded != null && forwarded.trim().isNotEmpty) {
        return forwarded.split(',').first.trim();
      }
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

  /// True when the request arrives over loopback or from an in-process
  /// caller (no socket at all, e.g. the desktop app driving its embedded
  /// server directly or handler-level tests).
  bool _isLocalRequest(Request request) {
    InternetAddress? remote;
    final connectionInfo = request.context['shelf.io.connection_info'];
    if (connectionInfo is HttpConnectionInfo) {
      remote = connectionInfo.remoteAddress;
    } else {
      final ioRequest = request.context['shelf.io.request'];
      if (ioRequest is HttpRequest) {
        remote = ioRequest.connectionInfo?.remoteAddress;
      }
    }
    return remote == null || remote.isLoopback;
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

  /// Error handling middleware.
  ///
  /// Details (exception + stack) go to the server log only; clients get a
  /// generic body so internals (paths, library state) never leak to the
  /// network.
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
            'message': 'An unexpected error occurred',
          });
        }
      };
    };
  }

  // Request bodies are read fully into memory by most JSON handlers, so a
  // client must not be able to send unbounded bodies. Avatar and playlist
  // cover uploads enforce their own 5 MB limit and get slack for it here.
  static const int _defaultMaxRequestBodyBytes = 2 * 1024 * 1024;
  static const int _uploadMaxRequestBodyBytes = 6 * 1024 * 1024;

  int _maxRequestBodyBytesForPath(String path) {
    if (path == '/api/me/avatar' ||
        (path.startsWith('/api/playlists/') && path.endsWith('/image'))) {
      return _uploadMaxRequestBodyBytes;
    }
    return _defaultMaxRequestBodyBytes;
  }

  /// Rejects oversized request bodies with 413 before handlers buffer them.
  ///
  /// A declared Content-Length over the cap is rejected outright; bodies
  /// without one (chunked uploads) are counted as they stream and cut off at
  /// the cap.
  Middleware _bodyLimitMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final path = '/${request.url.path}';
        // WebSocket upgrades hijack the underlying socket; leave them alone.
        if (path == '/api/ws') {
          return await handler(request);
        }

        final maxBytes = _maxRequestBodyBytesForPath(path);
        final declaredLength = request.contentLength;
        if (declaredLength != null && declaredLength > maxBytes) {
          return _requestBodyTooLargeResponse(maxBytes);
        }

        Stream<List<int>> limitedBody() async* {
          var total = 0;
          await for (final chunk in request.read()) {
            total += chunk.length;
            if (total > maxBytes) {
              throw const _RequestBodyTooLargeException();
            }
            yield chunk;
          }
        }

        try {
          return await handler(request.change(body: limitedBody()));
        } on _RequestBodyTooLargeException {
          return _requestBodyTooLargeResponse(maxBytes);
        }
      };
    };
  }

  Response _requestBodyTooLargeResponse(int maxBytes) {
    return _jsonResponse(HttpStatus.requestEntityTooLarge, {
      'error': {
        'code': 'REQUEST_TOO_LARGE',
        'message':
            'Request body exceeds the ${maxBytes ~/ (1024 * 1024)} MB limit',
      },
    });
  }

  // Query parameters that carry credentials and must never reach the log.
  static const Set<String> _sensitiveQueryParams = {
    'streamtoken',
    'downloadtoken',
    'registrationtoken',
    'sessiontoken',
    'bootstrapcode',
    'invitecode',
    'token',
  };

  /// Request logger replacing shelf's [logRequests]: media/artwork routes are
  /// logged without their query string (their tokens are the credential), and
  /// token-like query parameters are redacted everywhere else.
  Middleware _redactingRequestLogger() {
    return (Handler handler) {
      return (Request request) async {
        final stopwatch = Stopwatch()..start();
        final path = '/${request.url.path}';
        final query = _loggableQuery(path, request.url.queryParameters);

        try {
          final response = await handler(request);
          stopwatch.stop();
          print('${DateTime.now().toIso8601String()} '
              '${stopwatch.elapsed.inMilliseconds}ms '
              '${request.method} $path$query -> ${response.statusCode}');
          return response;
        } on HijackException {
          rethrow;
        } catch (e) {
          stopwatch.stop();
          print('${DateTime.now().toIso8601String()} '
              '${stopwatch.elapsed.inMilliseconds}ms '
              '${request.method} $path$query -> ERROR');
          rethrow;
        }
      };
    };
  }

  String _loggableQuery(String path, Map<String, String> queryParameters) {
    if (queryParameters.isEmpty) {
      return '';
    }

    final isMediaPath = path.startsWith('/api/stream') ||
        path.startsWith('/api/download') ||
        path.startsWith('/api/artwork/') ||
        path.startsWith('/api/song-artwork/');
    if (isMediaPath) {
      return '';
    }

    final parts = queryParameters.entries.map((entry) {
      final isSensitive =
          _sensitiveQueryParams.contains(entry.key.toLowerCase());
      return '${entry.key}=${isSensitive ? '<redacted>' : entry.value}';
    });
    return '?${parts.join('&')}';
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
  DateTime lastAttemptAt = DateTime.now();

  void touch() {
    lastAttemptAt = DateTime.now();
  }

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

class _RequestBodyTooLargeException implements Exception {
  const _RequestBodyTooLargeException();
}
