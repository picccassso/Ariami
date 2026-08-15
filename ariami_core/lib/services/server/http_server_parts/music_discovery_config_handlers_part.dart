part of '../http_server.dart';

extension AriamiHttpServerMusicDiscoveryConfigMethods on AriamiHttpServer {
  static const int _musicDiscoveryConfigSchemaVersion = 1;

  HouseholdMusicDiscoveryStore? get _musicDiscoveryStoreIfReady {
    final store = _householdMusicDiscoveryStore;
    return store != null && store.isInitialized ? store : null;
  }

  Response _musicDiscoveryStoreUnavailable() =>
      _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'MUSIC_DISCOVERY_CONFIG_UNAVAILABLE',
          'message': 'Music discovery configuration is not initialized',
        },
      });

  Map<String, dynamic> _musicDiscoveryConfigPayload(
    Request request,
    HouseholdMusicDiscoveryStore store,
  ) {
    final session = request.context['session'] as Session?;
    return <String, dynamic>{
      'schemaVersion': _musicDiscoveryConfigSchemaVersion,
      'lastFmApiKey': store.lastFmApiKey,
      'canManage': session != null && _authService.isAdminUser(session.userId),
    };
  }

  /// Any signed-in household device may read the shared application key.
  Future<Response> _handleMusicDiscoveryConfigGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _musicDiscoveryStoreIfReady;
    if (store == null) return _musicDiscoveryStoreUnavailable();
    return _jsonOk(_musicDiscoveryConfigPayload(request, store));
  }

  /// Owner-only: create or replace the household Last.fm API key.
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
    final key = decoded is Map<String, dynamic>
        ? HouseholdMusicDiscoveryStore.normalizeApiKey(
            decoded['lastFmApiKey'],
          )
        : null;
    if (key == null) {
      return _jsonResponse(HttpStatus.badRequest, {
        'error': {
          'code': 'INVALID_MUSIC_DISCOVERY_CONFIG',
          'message': 'Body must contain a non-empty "lastFmApiKey" string '
              'of at most ${HouseholdMusicDiscoveryStore.maxApiKeyBytes} bytes',
        },
      });
    }

    final onlyIfMissing =
        decoded is Map<String, dynamic> && decoded['onlyIfMissing'] == true;
    if (onlyIfMissing) {
      await store.saveIfEmpty(key);
    } else {
      await store.save(key);
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
}
