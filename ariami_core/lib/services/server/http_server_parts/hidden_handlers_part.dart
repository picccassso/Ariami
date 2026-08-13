part of '../http_server.dart';

/// Authenticated API for account-owned hidden items.
///
/// Hiding is a browsing preference, not a permission: these endpoints only say
/// what a client should leave out of its library lists. Nothing here affects
/// playback, search or what a stream request may reach.
extension AriamiHttpServerHiddenMethods on AriamiHttpServer {
  static const int _hiddenSchemaVersion = 1;

  HiddenItemStore? get _hiddenStoreIfReady {
    final store = _hiddenItemStore;
    return store != null && store.isInitialized ? store : null;
  }

  Response _hiddenUnavailable() =>
      _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'HIDDEN_UNAVAILABLE',
          'message': 'Hidden items storage is not initialized',
        },
      });

  Future<Response> _handleHiddenGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _hiddenStoreIfReady;
    if (store == null) return _hiddenUnavailable();

    final hidden = store.list(session.userId);
    final repository = _libraryManager.createCatalogRepository();
    final albums = repository == null
        ? const <String, CatalogAlbumRecord>{}
        : <String, CatalogAlbumRecord>{
            for (final album in repository.getAlbumsByIds(
              _hiddenTargetIds(hidden, HiddenItem.albumType),
            ))
              album.id: album,
          };
    final playlists = repository == null
        ? const <String, CatalogPlaylistRecord>{}
        : <String, CatalogPlaylistRecord>{
            for (final playlist in repository.getPlaylistsByIds(
              _hiddenTargetIds(hidden, HiddenItem.playlistType),
            ))
              playlist.id: playlist,
          };

    return _jsonOk({
      'schemaVersion': _hiddenSchemaVersion,
      // Each row carries a display name so the unhide UI can list something
      // the user recognises without re-deriving it from the catalog — and can
      // still name a target whose album has since left the library.
      'hidden': hidden.map((item) {
        final json = item.toJson();
        switch (item.type) {
          case HiddenItem.albumType:
            final album = albums[item.targetId];
            return <String, dynamic>{
              ...json,
              'name': album?.title ?? 'Unavailable album',
              'subtitle': album?.artist,
              'missing': album == null,
            };
          case HiddenItem.playlistType:
            final playlist = playlists[item.targetId];
            return <String, dynamic>{
              ...json,
              'name': playlist?.name ?? 'Unavailable playlist',
              'subtitle': playlist == null
                  ? null
                  : '${playlist.songCount} '
                      '${playlist.songCount == 1 ? 'song' : 'songs'}',
              'missing': playlist == null,
            };
          default:
            // Artists are credit strings, so the target id is the name and
            // nothing in the catalog can make it stale.
            return <String, dynamic>{
              ...json,
              'name': item.targetId,
              'subtitle': null,
              'missing': false,
            };
        }
      }).toList(growable: false),
    });
  }

  List<String> _hiddenTargetIds(List<HiddenItem> hidden, String type) => hidden
      .where((item) => item.type == type)
      .map((item) => item.targetId)
      .toList(growable: false);

  /// Hides one target, or a whole multi-selection when the body carries an
  /// `items` list. The batch form is all-or-nothing at the transaction level
  /// but skips individually invalid rows, so one bad entry cannot cost the
  /// user the rest of their selection.
  Future<Response> _handleHiddenPost(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _hiddenStoreIfReady;
    if (store == null) return _hiddenUnavailable();
    final body = await _readHiddenBody(request);
    if (body == null) {
      return _invalidHiddenRequest('Body must be a JSON object');
    }

    final rawItems = body['items'];
    final targets = <({String type, String targetId})>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final type = raw['type'];
        final targetId = raw['targetId'];
        if (type is String && targetId is String) {
          targets.add((type: type, targetId: targetId));
        }
      }
      if (targets.isEmpty) {
        return _invalidHiddenRequest('items must contain at least one entry');
      }
    } else {
      final type = body['type'];
      final targetId = body['targetId'];
      if (type is! String || !HiddenItem.supportedTypes.contains(type)) {
        return _invalidHiddenRequest('type must be album, playlist or artist');
      }
      if (targetId is! String || targetId.trim().isEmpty) {
        return _invalidHiddenRequest('targetId must be a non-empty string');
      }
      targets.add((type: type, targetId: targetId));
    }

    final before = store.list(session.userId).length;
    final hidden = store.hideAll(
      session.userId,
      targets,
      sourceDeviceId: session.deviceId,
    );
    if (store.list(session.userId).length > before) {
      _broadcastHiddenChanged(session, reason: 'hidden');
    }
    return _jsonOk({
      'schemaVersion': _hiddenSchemaVersion,
      'hidden': hidden.map((item) => item.toJson()).toList(growable: false),
      'skipped': targets.length - hidden.length,
    });
  }

  Future<Response> _handleHiddenDelete(
    Request request,
    String type,
    String targetId,
  ) async {
    final decodedType = Uri.decodeComponent(type);
    final decodedTargetId = Uri.decodeComponent(targetId);
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _hiddenStoreIfReady;
    if (store == null) return _hiddenUnavailable();
    if (!HiddenItem.supportedTypes.contains(decodedType)) {
      return _invalidHiddenRequest('type must be album, playlist or artist');
    }
    try {
      final removed = store.unhide(
        session.userId,
        decodedType,
        decodedTargetId,
      );
      if (removed) _broadcastHiddenChanged(session, reason: 'unhidden');
      return _jsonOk({'removed': removed});
    } on ArgumentError catch (error) {
      return _invalidHiddenRequest(
        error.message?.toString() ?? 'Invalid hidden item',
      );
    }
  }

  Future<Map<String, dynamic>?> _readHiddenBody(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Response _invalidHiddenRequest(String message) => _jsonBadRequest({
        'error': {'code': 'INVALID_HIDDEN_ITEM', 'message': message},
      });

  void _broadcastHiddenChanged(Session session, {required String reason}) {
    _connectHub.sendToUser(
      session.userId,
      WsMessage(
        type: WsMessageType.hiddenChanged,
        data: {'reason': reason, 'sourceDeviceId': session.deviceId},
      ),
      exceptDeviceId: session.deviceId,
    );
  }
}
