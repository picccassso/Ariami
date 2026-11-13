part of '../http_server.dart';

/// Authenticated API and admin endpoints for per-user library curation.
extension AriamiHttpServerCurationMethods on AriamiHttpServer {
  UserLibraryCurationStore? get _curationStoreIfReady {
    final store = _curationStore;
    return store != null && store.isInitialized ? store : null;
  }

  Response _curationUnavailable() => _jsonError(
        HttpStatus.serviceUnavailable,
        'CURATION_UNAVAILABLE',
        'Library curation storage is not initialized',
      );

  Response _invalidCurationRequest(String message) =>
      _jsonError(HttpStatus.badRequest, 'INVALID_CURATION', message);

  void _registerCurationRoutes(Router router) {
    router.get(
      '/api/v2/curation',
      (request) => _handleProtectedV2Request(request, _handleCurationGet),
    );
    router.put(
      '/api/v2/curation',
      (request) => _handleProtectedV2Request(request, _handleCurationPut),
    );
  }

  UserLibraryCuration _readUserCuration(String userId) {
    final store = _curationStoreIfReady!;
    final isAdmin = _authService.isAdminUser(userId);
    return store.getForUser(
      userId,
      defaultMode: LibraryCurationMode.full,
      defaultOnboardingCompleted: isAdmin,
    );
  }

  Future<Response> _handleCurationGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _curationStoreIfReady;
    if (store == null) return _curationUnavailable();

    return _jsonOk(_readUserCuration(session.userId).toJson());
  }

  Future<Response> _handleCurationPut(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _curationStoreIfReady;
    if (store == null) return _curationUnavailable();

    final body = await _readCurationBody(request);
    if (body == null) {
      return _invalidCurationRequest('Body must be a JSON object');
    }

    return _applyCurationUpdate(
      userId: session.userId,
      body: body,
      sourceDeviceId: session.deviceId,
      defaultOnboardingOnSave: true,
    );
  }

  Future<Response> _handleAdminGetUserCuration(
    Request request,
    String userId,
  ) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;
    final store = _curationStoreIfReady;
    if (store == null) return _curationUnavailable();

    final decodedUserId = Uri.decodeComponent(userId);
    if (_authService.getUserById(decodedUserId) == null) {
      return _jsonError(
          HttpStatus.notFound, 'USER_NOT_FOUND', 'User not found');
    }

    return _jsonOk(_readUserCuration(decodedUserId).toJson());
  }

  Future<Response> _handleAdminPutUserCuration(
    Request request,
    String userId,
  ) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;
    final store = _curationStoreIfReady;
    if (store == null) return _curationUnavailable();

    final decodedUserId = Uri.decodeComponent(userId);
    if (_authService.getUserById(decodedUserId) == null) {
      return _jsonError(
          HttpStatus.notFound, 'USER_NOT_FOUND', 'User not found');
    }

    final body = await _readCurationBody(request);
    if (body == null) {
      return _invalidCurationRequest('Body must be a JSON object');
    }

    // Do not exclude sender device when admin edits another user (or even self)
    // from dashboard so every player client updates immediately.
    return _applyCurationUpdate(
      userId: decodedUserId,
      body: body,
      sourceDeviceId: null,
      defaultOnboardingOnSave: body['onboardingCompleted'] as bool? ?? true,
    );
  }

  Future<Response> _handleAdminCurationCatalog(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    final repository = _libraryManager.createCatalogRepository();
    if (repository == null) {
      return _jsonOk({
        'albums': const <Map<String, dynamic>>[],
        'playlists': const <Map<String, dynamic>>[],
        'standaloneSongs': const <Map<String, dynamic>>[],
      });
    }

    final albums = _loadAllCatalogAlbums(repository)
        .map((album) => <String, dynamic>{
              'id': album.id,
              'title': album.title,
              'artist': album.artist,
              if (album.year != null) 'year': album.year,
              'songCount': album.songCount,
              'durationSeconds': album.durationSeconds,
            })
        .toList(growable: false);

    final playlists = _loadAllCatalogPlaylists(repository)
        .map((playlist) => <String, dynamic>{
              'id': playlist.id,
              'name': playlist.name,
              'songCount': playlist.songCount,
              'durationSeconds': playlist.durationSeconds,
            })
        .toList(growable: false);

    final standaloneSongs = _loadAllCatalogSongs(repository)
        .where((song) => song.albumId == null || song.albumId!.isEmpty)
        .map((song) => <String, dynamic>{
              'id': song.id,
              'title': song.title,
              'artist': song.artist,
              'durationSeconds': song.durationSeconds,
            })
        .toList(growable: false);

    return _jsonOk({
      'albums': albums,
      'playlists': playlists,
      'standaloneSongs': standaloneSongs,
    });
  }

  Future<Response> _handleAdminCurationSongs(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;

    final repository = _libraryManager.createCatalogRepository();
    if (repository == null) {
      return _jsonOk({'songs': const <Map<String, dynamic>>[]});
    }

    final albumId = request.url.queryParameters['albumId']?.trim();
    final query = request.url.queryParameters['q']?.trim().toLowerCase() ?? '';
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
    final cappedLimit = limit.clamp(1, 500);

    if (albumId != null && albumId.isNotEmpty) {
      final songs = repository
          .getSongsByAlbumIds(<String>[albumId])
          .map((song) => <String, dynamic>{
                'id': song.id,
                'title': song.title,
                'artist': song.artist,
                if (song.albumId != null) 'albumId': song.albumId,
                'durationSeconds': song.durationSeconds,
                if (song.trackNumber != null) 'trackNumber': song.trackNumber,
              })
          .toList(growable: false);
      return _jsonOk({'songs': songs});
    }

    final albumsById = <String, CatalogAlbumRecord>{
      for (final album in _loadAllCatalogAlbums(repository)) album.id: album,
    };

    final matched = <Map<String, dynamic>>[];
    for (final song in _loadAllCatalogSongs(repository)) {
      if (query.isNotEmpty) {
        final albumTitle = song.albumId != null
            ? (albumsById[song.albumId!]?.title.toLowerCase() ?? '')
            : '';
        final hit = song.title.toLowerCase().contains(query) ||
            song.artist.toLowerCase().contains(query) ||
            albumTitle.contains(query);
        if (!hit) continue;
      }
      final album = song.albumId != null ? albumsById[song.albumId!] : null;
      matched.add(<String, dynamic>{
        'id': song.id,
        'title': song.title,
        'artist': song.artist,
        if (song.albumId != null) 'albumId': song.albumId,
        if (album != null) 'albumTitle': album.title,
        'durationSeconds': song.durationSeconds,
        if (song.trackNumber != null) 'trackNumber': song.trackNumber,
      });
      if (matched.length >= cappedLimit) break;
    }

    return _jsonOk({'songs': matched});
  }

  Response _applyCurationUpdate({
    required String userId,
    required Map<String, dynamic> body,
    required String? sourceDeviceId,
    required bool defaultOnboardingOnSave,
  }) {
    final store = _curationStoreIfReady!;
    final current = _readUserCuration(userId);

    LibraryCurationMode mode = current.mode;
    if (body.containsKey('mode')) {
      final rawMode = body['mode'];
      if (rawMode != 'full' && rawMode != 'curated') {
        return _invalidCurationRequest('mode must be "full" or "curated"');
      }
      mode = LibraryCurationMode.fromWire(rawMode as String);
    }

    final onboardingCompleted = body.containsKey('onboardingCompleted')
        ? (body['onboardingCompleted'] as bool? ?? defaultOnboardingOnSave)
        : (current.onboardingCompleted || defaultOnboardingOnSave);

    var rules = current.rules;
    if (body.containsKey('rules')) {
      final rawRules = body['rules'];
      if (rawRules is! List) {
        return _invalidCurationRequest('rules must be a list');
      }
      final parsedRules = <CurationRuleEntry>[];
      for (final raw in rawRules) {
        if (raw is! Map) {
          return _invalidCurationRequest('Each rule must be a JSON object');
        }
        final entry = CurationRuleEntry.tryFromJson(
          Map<String, dynamic>.from(raw),
        );
        if (entry == null) {
          return _invalidCurationRequest(
            'Rule requires valid targetType, action, and non-empty targetId',
          );
        }
        parsedRules.add(entry);
      }
      rules = parsedRules;
    }

    final saved = store.saveForUser(
      userId,
      mode: mode,
      onboardingCompleted: onboardingCompleted,
      rules: rules,
      sourceDeviceId: sourceDeviceId,
    );

    _broadcastCurationChanged(
      userId,
      curation: saved,
      sourceDeviceId: sourceDeviceId,
    );
    return _jsonOk(saved.toJson());
  }

  void _broadcastCurationChanged(
    String userId, {
    required UserLibraryCuration curation,
    String? sourceDeviceId,
  }) {
    _connectHub.sendToUser(
      userId,
      WsMessage(
        type: WsMessageType.curationChanged,
        data: <String, dynamic>{
          'mode': curation.mode.wireName,
          'revision': curation.revision,
          if (sourceDeviceId != null) 'sourceDeviceId': sourceDeviceId,
        },
      ),
      exceptDeviceId: sourceDeviceId,
    );
  }

  Future<Map<String, dynamic>?> _readCurationBody(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  List<CatalogAlbumRecord> _loadAllCatalogAlbums(CatalogRepository repository) {
    final items = <CatalogAlbumRecord>[];
    String? cursor;
    while (true) {
      final page = repository.listAlbumsPage(cursor: cursor, limit: 500);
      items.addAll(page.items);
      if (!page.hasMore || page.nextCursor == null) break;
      cursor = page.nextCursor;
    }
    return items;
  }

  List<CatalogPlaylistRecord> _loadAllCatalogPlaylists(
      CatalogRepository repository) {
    final items = <CatalogPlaylistRecord>[];
    String? cursor;
    while (true) {
      final page = repository.listPlaylistsPage(cursor: cursor, limit: 500);
      items.addAll(page.items);
      if (!page.hasMore || page.nextCursor == null) break;
      cursor = page.nextCursor;
    }
    return items;
  }

  List<CatalogSongRecord> _loadAllCatalogSongs(CatalogRepository repository) {
    final items = <CatalogSongRecord>[];
    String? cursor;
    while (true) {
      final page = repository.listSongsPage(cursor: cursor, limit: 500);
      items.addAll(page.items);
      if (!page.hasMore || page.nextCursor == null) break;
      cursor = page.nextCursor;
    }
    return items;
  }
}
