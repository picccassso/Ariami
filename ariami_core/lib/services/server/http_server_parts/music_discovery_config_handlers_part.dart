part of '../http_server.dart';

extension AriamiHttpServerMusicDiscoveryConfigMethods on AriamiHttpServer {
  static const int _musicDiscoveryConfigSchemaVersion = 1;

  HouseholdMusicDiscoveryStore? get _musicDiscoveryStoreIfReady {
    final store = _householdMusicDiscoveryStore;
    return store != null && store.isInitialized ? store : null;
  }

  Response _musicDiscoveryStoreUnavailable() => _jsonError(
      HttpStatus.serviceUnavailable,
      'MUSIC_DISCOVERY_CONFIG_UNAVAILABLE',
      'Music discovery configuration is not initialized');

  Map<String, dynamic> _musicDiscoveryConfigPayload(
    Request request,
    HouseholdMusicDiscoveryStore store,
  ) {
    final session = request.context['session'] as Session?;
    final isAdmin = session != null && _authService.isAdminUser(session.userId);
    return <String, dynamic>{
      'schemaVersion': _musicDiscoveryConfigSchemaVersion,
      'lastFmApiKey': store.lastFmApiKey,
      'feedToken': store.feedToken,
      if (isAdmin && store.webhookUrl != null) 'webhookUrl': store.webhookUrl,
      'canManage': isAdmin,
    };
  }

  Map<String, dynamic> _musicDiscoveryWishlistPayload(
    Request request,
    HouseholdMusicDiscoveryStore store, {
    MusicRecommendation? savedItem,
  }) {
    final session = request.context['session'] as Session?;
    final isAdmin = session != null && _authService.isAdminUser(session.userId);
    return <String, dynamic>{
      if (savedItem != null) 'item': savedItem.toJson(),
      'items': store.wishlist.map((item) => item.toJson()).toList(),
      'feedToken': store.feedToken,
      if (isAdmin && store.webhookUrl != null) 'webhookUrl': store.webhookUrl,
      'canManage': isAdmin,
    };
  }

  /// Any signed-in household device may read the shared application key.
  Future<Response> _handleMusicDiscoveryConfigGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _musicDiscoveryStoreIfReady;
    if (store == null) return _musicDiscoveryStoreUnavailable();
    await store.ensureFeedTokenPersisted();
    return _jsonOk(_musicDiscoveryConfigPayload(request, store));
  }

  /// Owner-only: update the household Last.fm API key and/or wishlist webhook URL.
  Future<Response> _handleMusicDiscoveryConfigPut(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;
    final store = _musicDiscoveryStoreIfReady;
    if (store == null) return _musicDiscoveryStoreUnavailable();

    Object? decoded;
    try {
      decoded = jsonDecode(await request.readAsString());
    } catch (_) {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic>) {
      return _jsonError(
        HttpStatus.badRequest,
        'INVALID_MUSIC_DISCOVERY_CONFIG',
        'Body must be a JSON object',
      );
    }

    final hasKey = decoded.containsKey('lastFmApiKey');
    final hasWebhook = decoded.containsKey('webhookUrl');
    if (!hasKey && !hasWebhook) {
      return _jsonError(
        HttpStatus.badRequest,
        'INVALID_MUSIC_DISCOVERY_CONFIG',
        'Body must contain "lastFmApiKey" or "webhookUrl"',
      );
    }

    String? validatedKey;
    if (hasKey) {
      validatedKey =
          HouseholdMusicDiscoveryStore.normalizeApiKey(decoded['lastFmApiKey']);
      if (validatedKey == null) {
        return _jsonError(
            HttpStatus.badRequest,
            'INVALID_MUSIC_DISCOVERY_CONFIG',
            'Body must contain a non-empty "lastFmApiKey" string '
                'of at most ${HouseholdMusicDiscoveryStore.maxApiKeyBytes} bytes');
      }
    }

    String? validatedWebhook;
    if (hasWebhook) {
      final rawWebhook = decoded['webhookUrl'];
      if (rawWebhook != null && rawWebhook is! String) {
        return _jsonError(
          HttpStatus.badRequest,
          'INVALID_MUSIC_DISCOVERY_CONFIG',
          '"webhookUrl" must be a string or null',
        );
      }
      final trimmedWebhook = (rawWebhook as String? ?? '').trim();
      if (trimmedWebhook.isNotEmpty) {
        validatedWebhook =
            HouseholdMusicDiscoveryStore.normalizeWebhookUrl(trimmedWebhook);
        if (validatedWebhook == null) {
          return _jsonError(
            HttpStatus.badRequest,
            'INVALID_MUSIC_DISCOVERY_CONFIG',
            '"webhookUrl" must be an HTTP/HTTPS URL of at most '
                '${HouseholdMusicDiscoveryStore.maxWebhookUrlBytes} bytes',
          );
        }
      }
    }

    if (hasKey && validatedKey != null) {
      if (decoded['onlyIfMissing'] == true) {
        await store.saveIfEmpty(validatedKey);
      } else {
        await store.save(validatedKey);
      }
    }
    if (hasWebhook) {
      await store.saveWebhookUrl(validatedWebhook);
    }
    return _jsonOk(_musicDiscoveryConfigPayload(request, store));
  }

  /// Owner-only: remove the household key without changing per-device
  /// Discovery preferences.
  Future<Response> _handleMusicDiscoveryConfigDelete(Request request) async {
    final authResponse = _authorizeAdminRequest(request);
    if (authResponse != null) return authResponse;
    final store = _musicDiscoveryStoreIfReady;
    if (store == null) return _musicDiscoveryStoreUnavailable();
    await store.clear();
    return _jsonOk(_musicDiscoveryConfigPayload(request, store));
  }

  Future<Response> _handleMusicDiscoveryWishlistGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _musicDiscoveryStoreIfReady;
    if (store == null) return _musicDiscoveryStoreUnavailable();
    await store.ensureFeedTokenPersisted();
    await _pruneOwnedWishlistItems(store);
    return _jsonOk(_musicDiscoveryWishlistPayload(request, store));
  }

  Future<Response> _handleMusicDiscoveryWishlistPost(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _musicDiscoveryStoreIfReady;
    if (store == null) return _musicDiscoveryStoreUnavailable();

    Object? decoded;
    try {
      decoded = jsonDecode(await request.readAsString());
    } catch (_) {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic>) {
      return _jsonError(
        HttpStatus.badRequest,
        'INVALID_WISHLIST_ITEM',
        'Body must be a recommendation JSON object',
      );
    }

    var item = MusicRecommendation.fromJson(decoded);
    if (item.name.trim().isEmpty || !item.lastFmUrl.hasScheme) {
      return _jsonError(
        HttpStatus.badRequest,
        'INVALID_WISHLIST_ITEM',
        'Wishlist item requires a non-empty name and valid lastFmUrl',
      );
    }

    if (item.effectiveArtistMusicBrainzId == null &&
        item.effectiveArtist.isNotEmpty) {
      try {
        final resolved = await _musicBrainz.searchArtist(item.effectiveArtist);
        if (resolved != null) {
          item = item.copyWith(artistMusicBrainzId: resolved.id);
        }
      } catch (_) {}
    }

    final saved = await store.addWishlistItem(item);
    final webhookUrl = store.webhookUrl;
    if (webhookUrl != null) {
      unawaited(_fireWishlistWebhook(webhookUrl, saved));
    }
    return _jsonOk(
      _musicDiscoveryWishlistPayload(request, store, savedItem: saved),
    );
  }

  Future<Response> _handleMusicDiscoveryWishlistDelete(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _musicDiscoveryStoreIfReady;
    if (store == null) return _musicDiscoveryStoreUnavailable();

    var key = request.url.queryParameters['key']?.trim() ?? '';
    if (key.isEmpty) {
      try {
        final bodyText = await request.readAsString();
        if (bodyText.trim().isNotEmpty) {
          final decoded = jsonDecode(bodyText);
          if (decoded is Map<String, dynamic>) {
            key = (decoded['key'] as String? ?? '').trim();
          }
        }
      } catch (_) {}
    }
    if (key.isEmpty) {
      return _jsonError(
        HttpStatus.badRequest,
        'INVALID_WISHLIST_KEY',
        'Missing wishlist item key',
      );
    }

    await store.removeWishlistItem(key);
    return _jsonOk(_musicDiscoveryWishlistPayload(request, store));
  }

  Future<Response> _handleMusicDiscoveryWishlistFeedGet(Request request) async {
    final store = _musicDiscoveryStoreIfReady;
    if (store == null) return _musicDiscoveryStoreUnavailable();

    final session = request.context['session'] as Session?;
    final token = request.url.queryParameters['token']?.trim();
    if (session == null &&
        (token == null || !_constantTimeEquals(token, store.feedToken))) {
      return _authRequiredResponse();
    }

    await _pruneOwnedWishlistItems(store);
    final format =
        (request.url.queryParameters['format'] ?? 'lidarr').trim().toLowerCase();

    if (format == 'text') {
      final body = store.wishlist
          .map((item) => item.textLine)
          .where((line) => line.isNotEmpty)
          .join('\n');
      return Response.ok(
        body,
        headers: const <String, String>{
          'Content-Type': 'text/plain; charset=utf-8',
        },
      );
    }

    if (format == 'json') {
      return Response.ok(
        jsonEncode(store.wishlist.map((item) => item.toJson()).toList()),
        headers: const <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
        },
      );
    }

    final seenMbids = <String>{};
    final lidarr = <Map<String, dynamic>>[];
    for (final item in store.wishlist) {
      final mbid = item.effectiveArtistMusicBrainzId;
      if (mbid == null || mbid.isEmpty || !seenMbids.add(mbid)) continue;
      lidarr.add(<String, dynamic>{
        'MusicBrainzId': mbid,
        if (item.effectiveArtist.isNotEmpty)
          'ArtistName': item.effectiveArtist,
      });
    }
    return Response.ok(
      jsonEncode(lidarr),
      headers: const <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
      },
    );
  }

  Future<void> _pruneOwnedWishlistItems([
    HouseholdMusicDiscoveryStore? store,
  ]) async {
    final targetStore = store ?? _musicDiscoveryStoreIfReady;
    final library = _libraryManager.library;
    if (targetStore == null || library == null || targetStore.wishlist.isEmpty) {
      return;
    }
    final owned = OwnedMusicIndex(_ownedMusicTracksFromLibrary(library));
    await targetStore.removeOwnedWishlistItems(owned);
  }

  Iterable<OwnedMusicTrack> _ownedMusicTracksFromLibrary(
    LibraryStructure library,
  ) sync* {
    for (final album in library.albums.values) {
      for (final song in album.songs) {
        yield OwnedMusicTrack(
          title: song.title ?? '',
          artist: song.artist ?? '',
          album: song.album ?? album.title,
          albumArtist: song.albumArtist ?? album.artist,
        );
      }
    }
    for (final song in library.standaloneSongs) {
      yield OwnedMusicTrack(
        title: song.title ?? '',
        artist: song.artist ?? '',
        album: song.album,
        albumArtist: song.albumArtist,
      );
    }
  }

  Future<void> _fireWishlistWebhook(
    String webhookUrl,
    MusicRecommendation item,
  ) async {
    try {
      final uri = Uri.parse(webhookUrl);
      final client = http.Client();
      try {
        await client
            .post(
              uri,
              headers: const <String, String>{
                'Content-Type': 'application/json',
              },
              body: jsonEncode(<String, dynamic>{
                'event': 'music_discovery.wishlist_added',
                'item': <String, dynamic>{
                  ...item.toJson(),
                  'searchQuery': item.textLine,
                  'effectiveArtistMusicBrainzId':
                      item.effectiveArtistMusicBrainzId,
                },
              }),
            )
            .timeout(const Duration(seconds: 5));
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  static bool _constantTimeEquals(String a, String b) {
    final bytesA = utf8.encode(a);
    final bytesB = utf8.encode(b);
    if (bytesA.length != bytesB.length) return false;
    var diff = 0;
    for (var i = 0; i < bytesA.length; i++) {
      diff |= bytesA[i] ^ bytesB[i];
    }
    return diff == 0;
  }
}
