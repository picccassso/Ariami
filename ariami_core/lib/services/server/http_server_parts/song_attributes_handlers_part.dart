part of '../http_server.dart';

/// Externally supplied per-song attributes (e.g. from an audio analysis tool)
/// and attribute-based song queries. Attributes are library-wide; playlist
/// conditions resolve against the caller's own view of each playlist.
extension AriamiHttpServerSongAttributesMethods on AriamiHttpServer {
  static const int _maxSongAttributeItems = 500;
  static const int _maxSongAttributeKeyLength = 64;
  static const int _defaultSongQueryLimit = 100;
  static const int _maxSongQueryLimit = 500;

  Future<Response> _handleSongAttributesPut(Request request) async {
    final repository = _libraryManager.createCatalogRepository();
    if (repository == null) return _songAttributesUnavailable();
    final body = await _readSongAttributesBody(request);
    final items = body?['items'];
    if (items is! List ||
        items.isEmpty ||
        items.length > _maxSongAttributeItems) {
      return _invalidSongAttributesRequest(
        'items must be a list of 1 to $_maxSongAttributeItems entries',
      );
    }

    final songs = _liveCatalogSongs(repository);
    final liveIds = songs.map((song) => song.id).toSet();
    final idsByPath = {
      for (final song in songs) _relativeSongPath(song.filePath): song.id,
    };
    final updates = <String, Map<String, Object?>>{};
    final results = <Map<String, Object?>>[];
    for (final item in items) {
      final songId = item is Map ? item['songId'] : null;
      final path = item is Map ? item['path'] : null;
      final attributes = item is Map ? item['attributes'] : null;
      if (songId is! String? || path is! String? || (songId ?? path) == null) {
        return _invalidSongAttributesRequest(
            'each item needs a songId or path string');
      }
      if (attributes is! Map ||
          attributes.isEmpty ||
          attributes.entries.any((entry) =>
              entry.key is! String ||
              (entry.key as String).isEmpty ||
              (entry.key as String).length > _maxSongAttributeKeyLength ||
              (entry.value != null &&
                  !isValidSongAttributeValue(entry.value)))) {
        return _invalidSongAttributesRequest(
          'attributes must map keys of 1 to $_maxSongAttributeKeyLength '
          'characters to a bool, number, list of strings, or null to remove',
        );
      }

      final resolvedId = songId ?? idsByPath[path];
      if (resolvedId == null || !liveIds.contains(resolvedId)) {
        results.add({'status': 'not_found'});
        continue;
      }
      updates
          .putIfAbsent(resolvedId, () => <String, Object?>{})
          .addAll(attributes.cast<String, Object?>());
      results.add({'songId': resolvedId, 'status': 'updated'});
    }

    repository.songAttributes.apply(updates);
    return _jsonOk({'results': results});
  }

  Future<Response> _handleSongQuery(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final repository = _libraryManager.createCatalogRepository();
    if (repository == null) return _songAttributesUnavailable();
    final body = await _readSongAttributesBody(request);
    if (body == null) {
      return _invalidSongAttributesRequest('Body must be a JSON object');
    }

    final SongAttributeQuery query;
    try {
      query =
          SongAttributeQuery.parse(where: body['where'], sort: body['sort']);
    } on FormatException catch (error) {
      return _invalidSongAttributesRequest(error.message);
    }
    final limit = body['limit'] ?? _defaultSongQueryLimit;
    if (limit is! int || limit < 1 || limit > _maxSongQueryLimit) {
      return _invalidSongAttributesRequest(
          'limit must be an integer between 1 and $_maxSongQueryLimit');
    }
    final cursor = body['cursor'];
    final offset = cursor is String ? int.tryParse(cursor) : 0;
    if ((cursor != null && cursor is! String) || offset == null || offset < 0) {
      return _invalidSongAttributesRequest('cursor is invalid');
    }

    final songs = _liveCatalogSongs(repository);
    final attributes = repository.songAttributes.readAll();
    final edits = query.playlistIds.isEmpty
        ? const <PlaylistEdit>[]
        : _playlistEditStoreIfReady?.list(session.userId) ??
            const <PlaylistEdit>[];
    final liveIds = songs.map((song) => song.id).toSet();
    final playlistSongIds = {
      for (final playlistId in query.playlistIds)
        playlistId: _effectivePlaylistSongIds(
          repository,
          playlistId,
          edits.where((edit) => edit.playlistId == playlistId).firstOrNull,
          liveIds,
        ),
    };

    const noAttributes = <String, Object>{};
    final matched = songs
        .where((song) => query.matches(
            song.id, attributes[song.id] ?? noAttributes, playlistSongIds))
        .toList()
      ..sort((a, b) {
        final order = query.compare(
            attributes[a.id] ?? noAttributes, attributes[b.id] ?? noAttributes);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    final nextOffset = offset + limit;
    return _jsonOk({
      'songs': matched
          .skip(offset)
          .take(limit)
          .map((song) => {
                'id': song.id,
                'path': _relativeSongPath(song.filePath),
                'title': song.title,
                'artist': song.artist,
                'albumId': song.albumId,
                'genre': song.genre,
                'duration': song.durationSeconds,
                'trackNumber': song.trackNumber,
                'attributes': attributes[song.id] ?? noAttributes,
              })
          .toList(),
      'total': matched.length,
      'nextCursor': nextOffset < matched.length ? '$nextOffset' : null,
    });
  }

  List<CatalogSongRecord> _liveCatalogSongs(CatalogRepository repository) =>
      repository.listSongsPage(limit: 1 << 30).items;

  /// The caller's view of [playlistId]: the folder playlist with their edit
  /// applied, or an account-owned playlist's own song list.
  Set<String> _effectivePlaylistSongIds(
    CatalogRepository repository,
    String playlistId,
    PlaylistEdit? edit,
    Set<String> liveSongIds,
  ) =>
      reconcilePlaylistSongIds(
        baseSongIds: repository
            .listPlaylistSongs(playlistId)
            .map((item) => item.songId)
            .toList(),
        liveSongIds: liveSongIds,
        editSongIds: edit?.songIds,
        baseSnapshot: edit?.baseSnapshot,
      ).toSet();

  /// [filePath] relative to the music folder with `/` separators, so external
  /// tools can match tracks regardless of where the server mounts the folder.
  String _relativeSongPath(String filePath) {
    final root = _musicFolderPath;
    if (root == null || !p.isWithin(root, filePath)) return filePath;
    return p.split(p.relative(filePath, from: root)).join('/');
  }

  Future<Map<String, dynamic>?> _readSongAttributesBody(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Response _invalidSongAttributesRequest(String message) => _jsonBadRequest({
        'error': {'code': 'INVALID_SONG_ATTRIBUTES', 'message': message},
      });

  Response _songAttributesUnavailable() =>
      _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'CATALOG_UNAVAILABLE',
          'message': 'Catalog storage is not initialized',
        },
      });
}
