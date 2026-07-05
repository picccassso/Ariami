part of '../http_server.dart';

/// Authenticated API for server-owned album and playlist pins.
extension AriamiHttpServerPinsMethods on AriamiHttpServer {
  static const int _pinsSchemaVersion = 1;

  PinnedItemStore? get _pinsStoreIfReady {
    final store = _pinnedItemStore;
    return store != null && store.isInitialized ? store : null;
  }

  Response _pinsUnavailable() => _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'PINS_UNAVAILABLE',
          'message': 'Pinned items storage is not initialized',
        },
      });

  Future<Response> _handlePinsGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _pinsStoreIfReady;
    if (store == null) return _pinsUnavailable();

    final pins = store.list(session.userId);
    final repository = _libraryManager.createCatalogRepository();
    final albumIds = pins
        .where((pin) => pin.type == PinnedItem.albumType)
        .map((pin) => pin.targetId)
        .toList(growable: false);
    final playlistIds = pins
        .where((pin) => pin.type == PinnedItem.playlistType)
        .map((pin) => pin.targetId)
        .toList(growable: false);
    final albums = repository == null
        ? const <String, CatalogAlbumRecord>{}
        : <String, CatalogAlbumRecord>{
            for (final album in repository.getAlbumsByIds(albumIds))
              album.id: album,
          };
    final playlists = repository == null
        ? const <String, CatalogPlaylistRecord>{}
        : <String, CatalogPlaylistRecord>{
            for (final playlist in repository.getPlaylistsByIds(playlistIds))
              playlist.id: playlist,
          };

    return _jsonOk({
      'schemaVersion': _pinsSchemaVersion,
      'pins': pins.map((pin) {
        final json = pin.toJson();
        if (pin.type == PinnedItem.albumType) {
          final album = albums[pin.targetId];
          return <String, dynamic>{
            ...json,
            'title': album?.title ?? 'Unavailable album',
            'name': album?.title ?? 'Unavailable album',
            'subtitle': album?.artist,
            'artwork': album == null
                ? null
                : '/api/artwork/${Uri.encodeComponent(album.id)}',
            'missing': album == null,
            'unavailable': album == null,
          };
        }
        final playlist = playlists[pin.targetId];
        return <String, dynamic>{
          ...json,
          'title': playlist?.name ?? 'Unavailable playlist',
          'name': playlist?.name ?? 'Unavailable playlist',
          'subtitle': playlist == null
              ? null
              : '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
          // Playlist artwork is a client-built song mosaic in Ariami.
          'artwork': null,
          'missing': playlist == null,
          'unavailable': playlist == null,
        };
      }).toList(growable: false),
    });
  }

  Future<Response> _handlePinsPost(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _pinsStoreIfReady;
    if (store == null) return _pinsUnavailable();
    final body = await _readPinsBody(request);
    if (body == null) return _invalidPinsRequest('Body must be a JSON object');
    final type = body['type'];
    final targetId = body['targetId'];
    if (type is! String || !PinnedItem.supportedTypes.contains(type)) {
      return _invalidPinsRequest('type must be album or playlist');
    }
    if (targetId is! String || targetId.trim().isEmpty) {
      return _invalidPinsRequest('targetId must be a non-empty string');
    }
    try {
      final before = store.list(session.userId).length;
      final pin = store.pin(
        session.userId,
        type,
        targetId,
        sourceDeviceId: session.deviceId,
      );
      final created = store.list(session.userId).length > before;
      if (created) _broadcastPinsChanged(session, reason: 'pinned');
      return _jsonOk({'pin': pin.toJson(), 'created': created});
    } on ArgumentError catch (error) {
      return _invalidPinsRequest(error.message?.toString() ?? 'Invalid pin');
    }
  }

  Future<Response> _handlePinsDelete(
    Request request,
    String type,
    String targetId,
  ) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _pinsStoreIfReady;
    if (store == null) return _pinsUnavailable();
    if (!PinnedItem.supportedTypes.contains(type)) {
      return _invalidPinsRequest('type must be album or playlist');
    }
    try {
      final removed = store.unpin(session.userId, type, targetId);
      if (removed) _broadcastPinsChanged(session, reason: 'unpinned');
      return _jsonOk({'removed': removed});
    } on ArgumentError catch (error) {
      return _invalidPinsRequest(error.message?.toString() ?? 'Invalid pin');
    }
  }

  /// Backup restore endpoint. It accepts current object rows and legacy keys
  /// (`album:id` / `playlist:id`) while always applying them to the session
  /// user. Re-importing the same payload cannot create duplicate rows.
  Future<Response> _handlePinsImport(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _pinsStoreIfReady;
    if (store == null) return _pinsUnavailable();
    final body = await _readPinsBody(request);
    final rawPins = body?['pins'];
    if (body == null || rawPins is! List) {
      return _invalidPinsRequest('pins must be a list');
    }
    final pins = <Map<String, dynamic>>[];
    for (final raw in rawPins) {
      if (raw is Map) {
        pins.add(Map<String, dynamic>.from(raw));
      } else if (raw is String) {
        final separator = raw.indexOf(':');
        if (separator > 0 && separator < raw.length - 1) {
          pins.add({
            'type': raw.substring(0, separator),
            'targetId': raw.substring(separator + 1),
          });
        }
      }
    }
    final replace = body['replace'] == true;
    final count = store.import(
      session.userId,
      pins,
      replace: replace,
      sourceDeviceId: session.deviceId,
    );
    _broadcastPinsChanged(session, reason: 'imported');
    return _jsonOk({
      'schemaVersion': _pinsSchemaVersion,
      'imported': count,
      'pins': store.list(session.userId).map((pin) => pin.toJson()).toList(),
    });
  }

  Future<Map<String, dynamic>?> _readPinsBody(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Response _invalidPinsRequest(String message) => _jsonBadRequest({
        'error': {'code': 'INVALID_PIN', 'message': message},
      });

  void _broadcastPinsChanged(Session session, {required String reason}) {
    _connectHub.sendToUser(
      session.userId,
      WsMessage(
        type: WsMessageType.pinsChanged,
        data: {'reason': reason, 'sourceDeviceId': session.deviceId},
      ),
      exceptDeviceId: session.deviceId,
    );
  }
}
