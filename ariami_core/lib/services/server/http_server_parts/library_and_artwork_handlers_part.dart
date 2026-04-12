part of '../http_server.dart';

extension AriamiHttpServerLibraryAndArtworkHandlersMethods on AriamiHttpServer {
  /// Handle get albums request (placeholder for Phase 5)
  Response _handleGetAlbums(Request request) {
    return _jsonOk({
      'albums': [],
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Handle get songs request (placeholder for Phase 5)
  Response _handleGetSongs(Request request) {
    return _jsonOk({
      'songs': [],
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Handle get album detail request
  Future<Response> _handleGetAlbumDetail(
      Request request, String albumId) async {
    final baseUrl = 'http://${_advertisedIp ?? _tailscaleIp}:$_port';
    final albumDetail = await _libraryManager.getAlbumDetail(albumId, baseUrl);

    if (albumDetail == null) {
      return _jsonNotFound({
        'error': {
          'code': 'ALBUM_NOT_FOUND',
          'message': 'Album not found: $albumId',
        },
      });
    }

    return _jsonOk(albumDetail);
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
      return _jsonNotFound({
        'error': {
          'code': 'ARTWORK_NOT_FOUND',
          'message': 'Artwork not found for album: $albumId',
        },
      });
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
            maxConcurrent: AriamiHttpServer._defaultMaxConcurrentArtworkPerUser,
            maxQueue: AriamiHttpServer._defaultMaxArtworkQueuePerUser,
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
      return _jsonNotFound({
        'error': {
          'code': 'ARTWORK_NOT_FOUND',
          'message': 'Artwork not found for song: $songId',
        },
      });
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
            maxConcurrent: AriamiHttpServer._defaultMaxConcurrentArtworkPerUser,
            maxQueue: AriamiHttpServer._defaultMaxArtworkQueuePerUser,
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
        responseData = await _artworkService!.getArtwork(
          'song_$songId',
          artworkData,
          size,
        );
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
}
