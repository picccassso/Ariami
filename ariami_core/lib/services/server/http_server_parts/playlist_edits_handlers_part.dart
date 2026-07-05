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

  Future<Response> _handlePlaylistEditsGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _playlistEditStoreIfReady;
    if (store == null) return _playlistEditsUnavailable();

    final edits = store.list(session.userId);
    return _jsonOk({
      'schemaVersion': _playlistEditsSchemaVersion,
      'edits': edits.map((edit) => edit.toJson()).toList(growable: false),
    });
  }

  Future<Response> _handlePlaylistEditPut(
    Request request,
    String playlistId,
  ) async {
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
        playlistId,
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
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _playlistEditStoreIfReady;
    if (store == null) return _playlistEditsUnavailable();
    try {
      final removed = store.delete(session.userId, playlistId);
      if (removed) _broadcastPlaylistEditsChanged(session, reason: 'deleted');
      return _jsonOk({'removed': removed});
    } on ArgumentError catch (error) {
      return _invalidPlaylistEditRequest(
        error.message?.toString() ?? 'Invalid playlist edit',
      );
    }
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
