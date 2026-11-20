part of '../http_server.dart';

extension AriamiHttpServerLibraryAndArtworkHandlersMethods on AriamiHttpServer {
  /// Downsizes a custom playlist/artist photo when the client asks for a
  /// `?size=` preset; the original is served when no resize is possible.
  Future<(List<int>, String)> _sizedCustomImage(
    Request request,
    String cacheKey,
    Uint8List bytes,
    String contentType,
  ) async {
    final size = ArtworkSize.fromString(request.url.queryParameters['size']);
    final service = _artworkService;
    if (!size.requiresProcessing || service == null)
      return (bytes, contentType);
    final sized = await service.getArtwork(cacheKey, bytes, size);
    return identical(sized, bytes)
        ? (bytes, contentType)
        : (sized, 'image/jpeg');
  }

  Response _handleGetAlbums(Request request) {
    return _jsonOk({
      'albums': [],
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Response _handleGetSongs(Request request) {
    return _jsonOk({
      'songs': [],
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<Response> _handleGetAlbumDetail(
      Request request, String albumId) async {
    final baseUrl = _publicOrigin ??
        'http://${_advertisedIp ?? _tailscaleIp}:$_advertisedPort';
    final albumDetail = await _libraryManager.getAlbumDetail(albumId, baseUrl);

    if (albumDetail == null) {
      return _jsonError(
          HttpStatus.notFound, 'ALBUM_NOT_FOUND', 'Album not found: $albumId');
    }

    return _jsonOk(albumDetail);
  }

  static const int _maxBatchArtworkItems = 50;

  Future<ArtworkFormat> _resolveArtworkFormat(
    Request request,
    ArtworkSize size, {
    String? requestedFormat,
  }) async {
    final service = _artworkService;
    if (!size.requiresProcessing || service == null) return ArtworkFormat.jpeg;
    final queryFmt =
        (requestedFormat ?? request.url.queryParameters['format'])?.toLowerCase();
    final wantsWebp = queryFmt == 'webp' ||
        (queryFmt == null &&
            (request.headers['accept']?.toLowerCase().contains('image/webp') ??
                false));
    if (wantsWebp && await service.isWebpAvailable()) {
      return ArtworkFormat.webp;
    }
    return ArtworkFormat.jpeg;
  }

  Future<({List<int> bytes, String contentType, bool rateLimited})?>
      _resolveSizedArtwork(
    Request request, {
    required String cacheKey,
    required ArtworkSize size,
    required ArtworkFormat format,
    required Future<String?> Function() getStamp,
    required Future<List<int>?> Function() extractOriginal,
  }) async {
    final service = _artworkService;
    String? stamp;
    if (size.requiresProcessing && service != null) {
      stamp = await getStamp();
      if (stamp != null && stamp.isNotEmpty) {
        final cached = await service.getCachedArtwork(
          cacheKey,
          size,
          sourceStamp: stamp,
          format: format,
        );
        if (cached != null) {
          return (
            bytes: cached,
            contentType: format.contentType,
            rateLimited: false,
          );
        }
      }
    }

    final original = await extractOriginal();
    if (original == null) return null;

    if (!size.requiresProcessing || service == null) {
      return (bytes: original, contentType: 'image/jpeg', rateLimited: false);
    }

    String? artworkUserId;
    SimpleLimiter? artworkLimiter;
    if (_hasRegisteredUsers()) {
      artworkUserId = _resolveRequestUserId(request);
      if (artworkUserId != null) {
        artworkLimiter = _artworkUserLimiters.putIfAbsent(
          artworkUserId,
          () => SimpleLimiter(
            maxConcurrent: AriamiHttpServer._defaultMaxConcurrentArtworkPerUser,
            maxQueue: AriamiHttpServer._defaultMaxArtworkQueuePerUser,
          ),
        );
        if (!await artworkLimiter.acquire()) {
          return (
            bytes: const <int>[],
            contentType: 'image/jpeg',
            rateLimited: true,
          );
        }
      }
    }

    try {
      final processed = await service.getArtwork(
        cacheKey,
        original,
        size,
        format: format,
        sourceStamp: stamp,
      );
      final isOriginal = identical(processed, original);
      return (
        bytes: processed,
        contentType: isOriginal ? 'image/jpeg' : format.contentType,
        rateLimited: false,
      );
    } finally {
      if (artworkUserId != null && artworkLimiter != null) {
        artworkLimiter.release();
        if (artworkLimiter.isIdle) {
          _artworkUserLimiters.remove(artworkUserId);
        }
      }
    }
  }

  Response _artworkBinaryResponse(
    Request request,
    List<int> responseData, {
    required String contentType,
    required ArtworkSize size,
  }) {
    final etag = _computeArtworkEtag(responseData);
    final quotedEtag = '"$etag"';
    final lastModifiedHttp = HttpDate.format(_resolveArtworkLastModified());
    final commonHeaders = <String, String>{
      'ETag': quotedEtag,
      'Last-Modified': lastModifiedHttp,
      'Cache-Control': 'private, max-age=31536000, immutable',
      'Vary': 'Accept',
      'X-Artwork-Size': size.name,
    };

    if (_isMatchingEtag(request.headers['if-none-match'], etag)) {
      return Response.notModified(headers: commonHeaders);
    }

    return Response.ok(
      responseData,
      headers: {
        'Content-Type': contentType,
        ...commonHeaders,
      },
    );
  }

  Future<Response> _handleGetArtwork(Request request, String albumId) async {
    final authResponse = _authorizeArtworkRequest(
      request,
      requestedAlbumId: albumId,
    );
    if (authResponse != null) return authResponse;

    final size = ArtworkSize.fromString(request.url.queryParameters['size']);
    final format = await _resolveArtworkFormat(request, size);

    final resolved = await _resolveSizedArtwork(
      request,
      cacheKey: albumId,
      size: size,
      format: format,
      getStamp: () => _libraryManager.getAlbumArtworkSourceStamp(albumId),
      extractOriginal: () => _libraryManager.getAlbumArtwork(albumId),
    );

    if (resolved == null) {
      return _jsonError(HttpStatus.notFound, 'ARTWORK_NOT_FOUND',
          'Artwork not found for album: $albumId');
    }
    if (resolved.rateLimited) {
      return _retryableErrorResponse(
        statusCode: 429,
        error: 'Too many artwork requests',
        message: 'Per-user artwork request queue is full',
      );
    }

    return _artworkBinaryResponse(
      request,
      resolved.bytes,
      contentType: resolved.contentType,
      size: size,
    );
  }

  Future<Response> _handleGetSongArtwork(Request request, String songId) async {
    final authResponse = _authorizeArtworkRequest(
      request,
      requestedSongId: songId,
    );
    if (authResponse != null) return authResponse;

    final size = ArtworkSize.fromString(request.url.queryParameters['size']);
    final format = await _resolveArtworkFormat(request, size);

    final resolved = await _resolveSizedArtwork(
      request,
      cacheKey: 'song_$songId',
      size: size,
      format: format,
      getStamp: () => _libraryManager.getSongArtworkSourceStamp(songId),
      extractOriginal: () => _libraryManager.getSongArtwork(songId),
    );

    if (resolved == null) {
      return _jsonError(HttpStatus.notFound, 'ARTWORK_NOT_FOUND',
          'Artwork not found for song: $songId');
    }
    if (resolved.rateLimited) {
      return _retryableErrorResponse(
        statusCode: 429,
        error: 'Too many artwork requests',
        message: 'Per-user artwork request queue is full',
      );
    }

    return _artworkBinaryResponse(
      request,
      resolved.bytes,
      contentType: resolved.contentType,
      size: size,
    );
  }

  Future<Response> _handleBatchArtwork(Request request) async {
    if (!_hasRegisteredUsers() || request.context['session'] == null) {
      return _authRequiredResponse();
    }

    final Map<String, dynamic> body;
    try {
      body = await _readJsonBody(request);
    } catch (_) {
      return _jsonError(
        HttpStatus.badRequest,
        'INVALID_BODY',
        'Invalid JSON body',
      );
    }

    final size = ArtworkSize.fromString(
      (body['size'] as String?) ?? 'thumbnail',
    );
    final format = await _resolveArtworkFormat(
      request,
      size,
      requestedFormat: body['format'] as String?,
    );

    final rawAlbums = (body['albums'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();
    final rawSongs = (body['songs'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();

    final tasks = <Future<ArtworkBatchItem>>[];
    var count = 0;

    for (final albumId in rawAlbums) {
      if (count >= _maxBatchArtworkItems) break;
      count++;
      tasks.add(() async {
        final resolved = await _resolveSizedArtwork(
          request,
          cacheKey: albumId,
          size: size,
          format: format,
          getStamp: () => _libraryManager.getAlbumArtworkSourceStamp(albumId),
          extractOriginal: () => _libraryManager.getAlbumArtwork(albumId),
        );
        if (resolved == null || resolved.rateLimited) {
          return ArtworkBatchItem(
            key: ArtworkBatchCodec.albumKey(albumId),
            bytes: null,
          );
        }
        return ArtworkBatchItem(
          key: ArtworkBatchCodec.albumKey(albumId),
          bytes: resolved.bytes is Uint8List
              ? resolved.bytes as Uint8List
              : Uint8List.fromList(resolved.bytes),
          contentType: resolved.contentType,
        );
      }());
    }

    for (final songId in rawSongs) {
      if (count >= _maxBatchArtworkItems) break;
      count++;
      tasks.add(() async {
        final resolved = await _resolveSizedArtwork(
          request,
          cacheKey: 'song_$songId',
          size: size,
          format: format,
          getStamp: () => _libraryManager.getSongArtworkSourceStamp(songId),
          extractOriginal: () => _libraryManager.getSongArtwork(songId),
        );
        if (resolved == null || resolved.rateLimited) {
          return ArtworkBatchItem(
            key: ArtworkBatchCodec.songKey(songId),
            bytes: null,
          );
        }
        return ArtworkBatchItem(
          key: ArtworkBatchCodec.songKey(songId),
          bytes: resolved.bytes is Uint8List
              ? resolved.bytes as Uint8List
              : Uint8List.fromList(resolved.bytes),
          contentType: resolved.contentType,
        );
      }());
    }

    final items = await Future.wait(tasks);
    return Response.ok(
      ArtworkBatchCodec.encode(items),
      headers: const {
        'Content-Type': 'application/octet-stream',
        'Cache-Control': 'no-store',
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

  Future<Response> _handleGetLyrics(Request request, String songId) async {
    final lyrics = await _libraryManager.getSongLyrics(songId);
    if (lyrics == null) {
      return _jsonError(
        HttpStatus.notFound,
        'LYRICS_NOT_FOUND',
        'Lyrics not found for song: $songId',
      );
    }
    return _jsonOk(lyrics.toJson());
  }
}
