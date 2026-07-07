part of '../http_server.dart';

/// Authenticated API for account-scoped server playlist edits.
extension AriamiHttpServerPlaylistEditsMethods on AriamiHttpServer {
  static const int _playlistEditsSchemaVersion = 1;

  PlaylistEditStore? get _playlistEditStoreIfReady {
    final store = _playlistEditStore;
    return store != null && store.isInitialized ? store : null;
  }

  Response _playlistEditsUnavailable() =>
      _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'PLAYLIST_EDITS_UNAVAILABLE',
          'message': 'Playlist edit storage is not initialized',
        },
      });

  PlaylistImageStore? get _playlistImageStoreIfReady {
    final store = _playlistImageStore;
    return store != null && store.isInitialized ? store : null;
  }

  Future<Response> _handlePlaylistEditsGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _playlistEditStoreIfReady;
    if (store == null) return _playlistEditsUnavailable();

    final edits = store.list(session.userId);
    // Custom playlist cover images ride along with the edits so every client
    // learns about image changes from the fetch it already performs on each
    // playlistEditsChanged notification.
    final images = _playlistImageStoreIfReady?.list(session.userId) ??
        const <PlaylistImageInfo>[];
    return _jsonOk({
      'schemaVersion': _playlistEditsSchemaVersion,
      'edits': edits.map((edit) => edit.toJson()).toList(growable: false),
      'images': images.map((image) => image.toJson()).toList(growable: false),
    });
  }

  Future<Response> _handlePlaylistEditPut(
    Request request,
    String playlistId,
  ) async {
    final decodedPlaylistId = Uri.decodeComponent(playlistId);
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _playlistEditStoreIfReady;
    if (store == null) return _playlistEditsUnavailable();
    final body = await _readPlaylistEditBody(request);
    if (body == null) {
      return _invalidPlaylistEditRequest('Body must be a JSON object');
    }

    final rawSongIds = body['songIds'];
    final rawBaseSnapshot = body['baseSnapshot'];
    final rawName = body['name'];
    if (rawSongIds is! List ||
        rawSongIds.any((item) => item is! String || item.trim().isEmpty)) {
      return _invalidPlaylistEditRequest(
        'songIds must be a list of non-empty strings',
      );
    }
    if (rawBaseSnapshot is! List ||
        rawBaseSnapshot.any((item) => item is! String)) {
      return _invalidPlaylistEditRequest(
        'baseSnapshot must be a list of strings',
      );
    }
    if (rawName != null && rawName is! String) {
      return _invalidPlaylistEditRequest('name must be a string or null');
    }

    try {
      final edit = store.put(
        session.userId,
        decodedPlaylistId,
        songIds: rawSongIds.cast<String>(),
        name: rawName as String?,
        baseSnapshot: rawBaseSnapshot.cast<String>(),
        sourceDeviceId: session.deviceId,
      );
      _broadcastPlaylistEditsChanged(session, reason: 'edited');
      return _jsonOk({'edit': edit.toJson()});
    } on ArgumentError catch (error) {
      return _invalidPlaylistEditRequest(
        error.message?.toString() ?? 'Invalid playlist edit',
      );
    }
  }

  Future<Response> _handlePlaylistEditDelete(
    Request request,
    String playlistId,
  ) async {
    final decodedPlaylistId = Uri.decodeComponent(playlistId);
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _playlistEditStoreIfReady;
    if (store == null) return _playlistEditsUnavailable();
    try {
      final removed = store.delete(session.userId, decodedPlaylistId);
      // A created playlist lives only in the edit store, so deleting its edit
      // deletes the playlist itself — drop its cover image with it. Folder
      // playlists keep theirs: their edit delete is just a revert to base.
      if (removed && isCreatedPlaylistId(decodedPlaylistId)) {
        try {
          _playlistImageStoreIfReady?.delete(
            session.userId,
            decodedPlaylistId,
          );
        } on ArgumentError {
          // The edit id validated, so this cannot fire; keep the delete OK.
        }
      }
      if (removed) _broadcastPlaylistEditsChanged(session, reason: 'deleted');
      return _jsonOk({'removed': removed});
    } on ArgumentError catch (error) {
      return _invalidPlaylistEditRequest(
        error.message?.toString() ?? 'Invalid playlist edit',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Playlist cover images
  // ---------------------------------------------------------------------------

  static const Map<String, String> _playlistImageContentTypes =
      <String, String>{
    'image/jpeg': 'image/jpeg',
    'image/png': 'image/png',
    'image/webp': 'image/webp',
  };

  Response _playlistImagesUnavailable() =>
      _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'PLAYLIST_IMAGES_UNAVAILABLE',
          'message': 'Playlist image storage is not initialized',
        },
      });

  Response _badPlaylistImageResponse() => _jsonBadRequest({
        'error': {
          'code': 'INVALID_PLAYLIST_IMAGE',
          'message': 'Image must be a valid JPEG, PNG, or WebP file',
        },
      });

  Response _playlistImageTooLargeResponse() =>
      _jsonResponse(HttpStatus.requestEntityTooLarge, {
        'error': {
          'code': 'PLAYLIST_IMAGE_TOO_LARGE',
          'message': 'Image exceeds the '
              '${PlaylistImageStore.maxImageBytes ~/ (1024 * 1024)} MB limit',
        },
      });

  Future<Response> _handlePlaylistImageGet(
    Request request,
    String playlistId,
  ) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _playlistImageStoreIfReady;
    if (store == null) return _playlistImagesUnavailable();

    final PlaylistImageRecord? image;
    try {
      image = store.find(session.userId, Uri.decodeComponent(playlistId));
    } on ArgumentError {
      return _badPlaylistImageResponse();
    }
    if (image == null) return Response.notFound('');
    return Response.ok(
      image.bytes,
      headers: {
        'Content-Type': image.contentType,
        'Content-Length': image.bytes.length.toString(),
        // Clients cache-bust via the updatedAt version in the URL, so served
        // bytes are immutable for a given URL.
        'Cache-Control': 'public, max-age=31536000, immutable',
      },
    );
  }

  Future<Response> _handlePlaylistImagePut(
    Request request,
    String playlistId,
  ) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _playlistImageStoreIfReady;
    if (store == null) return _playlistImagesUnavailable();

    final contentType = _playlistImageContentTypes[request.mimeType];
    if (contentType == null) return _badPlaylistImageResponse();

    final declaredLength = request.contentLength;
    if (declaredLength != null &&
        declaredLength > PlaylistImageStore.maxImageBytes) {
      await request.read().drain<void>();
      return _playlistImageTooLargeResponse();
    }

    // On overflow the rest of the body is drained without buffering;
    // responding mid-upload severs the connection before the client can
    // read the 413.
    final bytesBuilder = BytesBuilder(copy: false);
    var totalBytes = 0;
    var tooLarge = false;
    await for (final chunk in request.read()) {
      if (tooLarge) continue;
      totalBytes += chunk.length;
      if (totalBytes > PlaylistImageStore.maxImageBytes) {
        tooLarge = true;
        bytesBuilder.clear();
        continue;
      }
      bytesBuilder.add(chunk);
    }
    if (tooLarge) return _playlistImageTooLargeResponse();

    final bytes = bytesBuilder.takeBytes();
    if (!_playlistImageMagicMatches(bytes, contentType)) {
      return _badPlaylistImageResponse();
    }

    try {
      final image = store.put(
        session.userId,
        Uri.decodeComponent(playlistId),
        bytes: bytes,
        contentType: contentType,
      );
      _broadcastPlaylistEditsChanged(session, reason: 'image');
      return _jsonOk({'image': image.toJson()});
    } on ArgumentError catch (error) {
      return _invalidPlaylistEditRequest(
        error.message?.toString() ?? 'Invalid playlist image',
      );
    }
  }

  Future<Response> _handlePlaylistImageDelete(
    Request request,
    String playlistId,
  ) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _playlistImageStoreIfReady;
    if (store == null) return _playlistImagesUnavailable();

    try {
      final removed =
          store.delete(session.userId, Uri.decodeComponent(playlistId));
      if (removed) _broadcastPlaylistEditsChanged(session, reason: 'image');
      return _jsonOk({'removed': removed});
    } on ArgumentError catch (error) {
      return _invalidPlaylistEditRequest(
        error.message?.toString() ?? 'Invalid playlist image',
      );
    }
  }

  bool _playlistImageMagicMatches(List<int> bytes, String contentType) {
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

  Future<Map<String, dynamic>?> _readPlaylistEditBody(
    Request request,
  ) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Response _invalidPlaylistEditRequest(String message) => _jsonBadRequest({
        'error': {'code': 'INVALID_PLAYLIST_EDIT', 'message': message},
      });

  void _broadcastPlaylistEditsChanged(
    Session session, {
    required String reason,
  }) {
    _connectHub.sendToUser(
      session.userId,
      WsMessage(
        type: WsMessageType.playlistEditsChanged,
        data: {'reason': reason, 'sourceDeviceId': session.deviceId},
      ),
      exceptDeviceId: session.deviceId,
    );
  }
}
