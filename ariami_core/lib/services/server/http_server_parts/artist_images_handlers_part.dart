part of '../http_server.dart';

/// Authenticated API for account-scoped custom artist photos.
extension AriamiHttpServerArtistImagesMethods on AriamiHttpServer {
  ArtistImageStore? get _artistImageStoreIfReady {
    final store = _artistImageStore;
    return store != null && store.isInitialized ? store : null;
  }

  Response _artistImagesUnavailable() =>
      _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'ARTIST_IMAGES_UNAVAILABLE',
          'message': 'Artist image storage is not initialized',
        },
      });

  static const Map<String, String> _artistImageContentTypes =
      <String, String>{
    'image/jpeg': 'image/jpeg',
    'image/png': 'image/png',
    'image/webp': 'image/webp',
  };

  Response _badArtistImageResponse() => _jsonBadRequest({
        'error': {
          'code': 'INVALID_ARTIST_IMAGE',
          'message': 'Image must be a valid JPEG, PNG, or WebP file',
        },
      });

  Response _artistImageTooLargeResponse() =>
      _jsonResponse(HttpStatus.requestEntityTooLarge, {
        'error': {
          'code': 'ARTIST_IMAGE_TOO_LARGE',
          'message': 'Image exceeds the '
              '${ArtistImageStore.maxImageBytes ~/ (1024 * 1024)} MB limit',
        },
      });

  /// Lists all custom artist images for the authenticated user.
  Future<Response> _handleArtistImagesGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _artistImageStoreIfReady;
    if (store == null) return _artistImagesUnavailable();

    final images = store.list(session.userId);
    return _jsonOk({
      'images': images.map((image) => image.toJson()).toList(growable: false),
    });
  }

  /// Serves the raw image bytes for an artist's custom image.
  Future<Response> _handleArtistImageGet(
    Request request,
    String artistName,
  ) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _artistImageStoreIfReady;
    if (store == null) return _artistImagesUnavailable();

    final ArtistImageRecord? image;
    try {
      image = store.find(session.userId, Uri.decodeComponent(artistName));
    } on ArgumentError {
      return _badArtistImageResponse();
    }
    if (image == null) return Response.notFound('');

    final etag = _computeArtworkEtag(image.bytes);
    final quotedEtag = '"$etag"';
    final ifNoneMatch = request.headers['if-none-match'];
    if (_isMatchingEtag(ifNoneMatch, etag)) {
      return Response.notModified(
        headers: {
          'ETag': quotedEtag,
          'Cache-Control': 'public, max-age=31536000, immutable',
        },
      );
    }

    return Response.ok(
      image.bytes,
      headers: {
        'Content-Type': image.contentType,
        'Content-Length': image.bytes.length.toString(),
        'ETag': quotedEtag,
        'Cache-Control': 'public, max-age=31536000, immutable',
      },
    );
  }

  /// Stores or replaces the custom image for an artist.
  Future<Response> _handleArtistImagePut(
    Request request,
    String artistName,
  ) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _artistImageStoreIfReady;
    if (store == null) return _artistImagesUnavailable();

    final contentType = _artistImageContentTypes[request.mimeType];
    if (contentType == null) return _badArtistImageResponse();

    final declaredLength = request.contentLength;
    if (declaredLength != null &&
        declaredLength > ArtistImageStore.maxImageBytes) {
      await request.read().drain<void>();
      return _artistImageTooLargeResponse();
    }

    final bytesBuilder = BytesBuilder(copy: false);
    var totalBytes = 0;
    var tooLarge = false;
    await for (final chunk in request.read()) {
      if (tooLarge) continue;
      totalBytes += chunk.length;
      if (totalBytes > ArtistImageStore.maxImageBytes) {
        tooLarge = true;
        bytesBuilder.clear();
        continue;
      }
      bytesBuilder.add(chunk);
    }
    if (tooLarge) return _artistImageTooLargeResponse();

    final bytes = bytesBuilder.takeBytes();
    if (!_artistImageMagicMatches(bytes, contentType)) {
      return _badArtistImageResponse();
    }

    try {
      final decodedName = Uri.decodeComponent(artistName);
      final image = store.put(
        session.userId,
        decodedName,
        bytes: bytes,
        contentType: contentType,
      );
      _broadcastArtistImagesChanged(
        session,
        reason: 'image',
        artistKey: image.artistKey,
      );
      return _jsonOk({'image': image.toJson()});
    } on ArgumentError catch (error) {
      return _invalidArtistImageRequest(
        error.message?.toString() ?? 'Invalid artist image',
      );
    }
  }

  /// Deletes a custom artist image.
  Future<Response> _handleArtistImageDelete(
    Request request,
    String artistName,
  ) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _artistImageStoreIfReady;
    if (store == null) return _artistImagesUnavailable();

    try {
      final decodedName = Uri.decodeComponent(artistName);
      final removed = store.delete(session.userId, decodedName);
      if (removed) {
        _broadcastArtistImagesChanged(
          session,
          reason: 'delete',
          artistKey: normalizeArtistKey(decodedName),
        );
      }
      return _jsonOk({'removed': removed});
    } on ArgumentError catch (error) {
      return _invalidArtistImageRequest(
        error.message?.toString() ?? 'Invalid artist image',
      );
    }
  }

  bool _artistImageMagicMatches(List<int> bytes, String contentType) {
    switch (contentType) {
      case 'image/jpeg':
        return bytes.length >= 3 &&
            bytes[0] == 0xFF &&
            bytes[1] == 0xD8 &&
            bytes[2] == 0xFF;
      case 'image/png':
        return bytes.length >= 4 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47;
      case 'image/webp':
        // RIFF....WEBP
        return bytes.length >= 12 &&
            bytes[0] == 0x52 &&
            bytes[1] == 0x49 &&
            bytes[2] == 0x46 &&
            bytes[3] == 0x46 &&
            bytes[8] == 0x57 &&
            bytes[9] == 0x45 &&
            bytes[10] == 0x42 &&
            bytes[11] == 0x50;
    }
    return false;
  }

  Response _invalidArtistImageRequest(String message) => _jsonBadRequest({
        'error': {'code': 'INVALID_ARTIST_IMAGE', 'message': message},
      });

  void _broadcastArtistImagesChanged(
    Session session, {
    required String reason,
    String? artistKey,
  }) {
    _connectHub.sendToUser(
      session.userId,
      WsMessage(
        type: WsMessageType.artistImagesChanged,
        data: {
          'reason': reason,
          if (artistKey != null) 'artistKey': artistKey,
          'sourceDeviceId': session.deviceId,
        },
      ),
      exceptDeviceId: session.deviceId,
    );
  }
}
