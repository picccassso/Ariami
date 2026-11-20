import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/services/recommendations/lastfm_recommendation_client.dart';
import 'package:ariami_core/services/recommendations/music_discovery_api_key_sync.dart';
import 'package:ariami_core/services/recommendations/music_recommendation_models.dart';
import 'package:ariami_core/services/recommendations/music_recommendation_seeds.dart';
import 'package:ariami_core/services/recommendations/music_recommendation_service.dart';
import 'package:ariami_core/services/recommendations/musicbrainz_identity_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_models.dart';
import 'connection_controller.dart';
import 'library_controller.dart';
import 'listening_stats_controller.dart';
import 'music_discovery_api_key_store.dart';
import 'player_api_client.dart';

const String _embeddedLastFmApiKey =
    String.fromEnvironment('ARIAMI_LASTFM_API_KEY');

enum DiscoveryErrorKind { general, invalidApiKey, rateLimited }

class MusicDiscoveryController extends ChangeNotifier {
  static const _enabledKey = 'desktop_music_discovery_enabled_v1';
  static const _preferencesKey = 'desktop_music_discovery_preferences_v1';
  static const _dismissedKey = 'desktop_music_discovery_dismissed_v1';
  static const _wishlistKey = 'desktop_music_discovery_wishlist_v1';
  static const _lastScopeKey = 'desktop_music_discovery_last_scope_v1';
  static const _cacheKey = 'desktop_music_discovery_cache_v9';
  static const _maxCacheEntries = 8;
  static const _legacyCachePrefixes = <String>[
    'desktop_music_discovery_cache_v1_',
    'desktop_music_discovery_cache_v2_',
    'desktop_music_discovery_cache_v3_',
    'desktop_music_discovery_cache_v4_',
    'desktop_music_discovery_cache_v5_',
    'desktop_music_discovery_cache_v6_',
    'desktop_music_discovery_cache_v7_',
    'desktop_music_discovery_cache_v8_',
  ];
  static const _refreshAge = Duration(hours: 24);

  final MusicDiscoveryApiKeyStore _apiKeyStore;
  final Future<String?> Function()? _readLegacyApiKey;
  final MusicBrainzIdentityClient _musicBrainz = MusicBrainzIdentityClient();
  LastFmRecommendationClient? _lastFm;

  MusicDiscoveryController({
    MusicDiscoveryApiKeyStore apiKeyStore = const MusicDiscoveryApiKeyStore(),
    Future<String?> Function()? readLegacyApiKey,
  })  : _apiKeyStore = apiKeyStore,
        _readLegacyApiKey = readLegacyApiKey;

  ConnectionController? _connection;
  LibraryController? _library;
  ListeningStatsController? _stats;

  MusicDiscoveryApiKeySync? _apiKeySync;
  MusicDiscoveryApiKeySyncState _apiKeyState =
      const MusicDiscoveryApiKeySyncState(
    embeddedKey: null,
    localKey: null,
    householdKey: null,
    remoteConfig: null,
  );

  MusicRecommendationSnapshot? _rawSnapshot;
  MusicRecommendationSnapshot? _filteredSnapshot;
  List<Track>? _lastFilteredSongs;

  String? _error;
  DiscoveryErrorKind _errorKind = DiscoveryErrorKind.general;
  bool _coldStart = false;
  bool _enabled = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _showSeeds = false;
  bool _initialized = false;
  bool _wasActiveSession = false;
  bool _pendingRefreshAfterLibraryLoad = false;
  bool _disposed = false;

  int _refreshToken = 0;
  int _syncGeneration = 0;
  PlayerApiClient? _syncedClient;
  String? _syncedScope;
  String? _lastConnectedScope;

  Set<String> _dismissedKeys = <String>{};
  List<MusicRecommendation> _wishlist = const <MusicRecommendation>[];
  bool _showSavedOnly = false;
  String? _feedToken;
  String? _webhookUrl;
  bool _remoteCanManage = false;
  MusicDiscoveryPreferences _preferences = const MusicDiscoveryPreferences();

  MusicRecommendationSnapshot? get snapshot => _filteredSnapshot;
  MusicDiscoveryApiKeySyncState get apiKeyState => _apiKeyState;
  bool get isEmbeddedApiKey => _embeddedLastFmApiKey.isNotEmpty;
  bool get hasLocalKey => !isEmbeddedApiKey && _apiKeyState.localKey != null;
  String get _effectiveApiKey => _apiKeyState.effectiveKey ?? '';
  bool get hasApiKey => _effectiveApiKey.isNotEmpty;
  String? get error => _error;
  DiscoveryErrorKind get errorKind => _errorKind;
  bool get coldStart => _coldStart;
  bool get enabled => _enabled;
  bool get loading => _loading;
  bool get refreshing => _refreshing;
  bool get showSeeds => _showSeeds;
  Set<String> get dismissedKeys => _dismissedKeys;
  List<MusicRecommendation> get wishlist => _wishlist;
  bool get showSavedOnly => _showSavedOnly;
  String? get feedToken => _feedToken ?? _apiKeyState.remoteConfig?.feedToken;
  String? get webhookUrl =>
      _webhookUrl ?? _apiKeyState.remoteConfig?.webhookUrl;
  bool get canManageHousehold =>
      _apiKeyState.canManageHousehold || _remoteCanManage;
  MusicDiscoveryPreferences get preferences => _preferences;

  bool isWishlisted(MusicRecommendation item) =>
      _wishlist.any((entry) => entry.identityKey == item.identityKey);

  String? feedUrlFor({String format = 'lidarr'}) {
    final baseUrl = _connection?.client?.baseUrl;
    final token = feedToken;
    if (baseUrl == null || baseUrl.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return Uri.parse('$baseUrl/api/music-discovery/wishlist/feed')
        .replace(queryParameters: <String, String>{
      'format': format,
      'token': token,
    }).toString();
  }

  bool get _isOffline {
    final connection = _connection;
    return connection == null ||
        connection.isOfflineActive ||
        !connection.isConnected;
  }

  void attach({
    required ConnectionController connection,
    required LibraryController library,
    required ListeningStatsController stats,
  }) {
    if (!identical(_connection, connection)) {
      _connection?.removeListener(_onConnectionChanged);
      _connection = connection..addListener(_onConnectionChanged);
    }
    if (!identical(_library, library)) {
      _library?.removeListener(_onLibraryChanged);
      _library = library..addListener(_onLibraryChanged);
    }
    _stats = stats;
    _onConnectionChanged();
  }

  void _onConnectionChanged() {
    if (_disposed) return;
    unawaited(_syncConnection());
  }

  void _onLibraryChanged() {
    if (_disposed) return;
    final library = _library;
    if (library == null) return;
    final songs = library.songs;
    final songsChanged = !identical(songs, _lastFilteredSongs);
    var filterChanged = false;
    if (songsChanged) {
      final prevCount = _filteredSnapshot?.recommendations.length;
      final prevWishCount = _wishlist.length;
      _applyLibraryFilter();
      filterChanged = _filteredSnapshot?.recommendations.length != prevCount ||
          _wishlist.length != prevWishCount;
    }

    if (_pendingRefreshAfterLibraryLoad && !library.isLoading) {
      _pendingRefreshAfterLibraryLoad = false;
      if (_enabled && hasApiKey && _isStale(_rawSnapshot) && !_isOffline) {
        unawaited(refresh());
      } else if (_errorKind == DiscoveryErrorKind.general && _error != null) {
        _error = null;
        filterChanged = true;
      }
    }

    if (filterChanged || songsChanged && _rawSnapshot != null) {
      notifyListeners();
    }
  }

  Future<void> _syncConnection() async {
    final connection = _connection;
    if (_disposed || connection == null) return;
    final gen = ++_syncGeneration;
    final stage = connection.stage;

    if (connection.isConnected) {
      _wasActiveSession = true;
      final scopes = _identityScopes(connection);
      final primaryScope = scopes.first;
      final client = connection.client;
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || gen != _syncGeneration) return;

      final savedScope = prefs.getString(_lastScopeKey);
      final accountChanged = (_lastConnectedScope != null &&
              !scopes.contains(_lastConnectedScope)) ||
          (savedScope != null && !scopes.contains(savedScope));

      if (accountChanged) {
        await _clearAccountScopedState(prefs);
        if (_disposed || gen != _syncGeneration) return;
      }
      _lastConnectedScope = primaryScope;
      await prefs.setString(_lastScopeKey, primaryScope);
      if (_disposed || gen != _syncGeneration) return;

      if (!_initialized ||
          !identical(client, _syncedClient) ||
          primaryScope != _syncedScope) {
        await _loadState(
          prefs,
          scopes,
          client,
          allowRefresh: true,
          generation: gen,
        );
      }
      return;
    }

    if (connection.isOfflineActive) {
      _wasActiveSession = true;
      if (_initialized) return;
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || gen != _syncGeneration) return;
      final scopes = _identityScopes(
        connection,
        fallbackScope: prefs.getString(_lastScopeKey),
      );
      await _loadState(
        prefs,
        scopes,
        null,
        allowRefresh: false,
        generation: gen,
      );
      return;
    }

    if (stage == ConnectionStage.connecting && _wasActiveSession) {
      return;
    }

    if (_wasActiveSession) {
      _wasActiveSession = false;
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || gen != _syncGeneration) return;
      await _resetOnDisconnect(prefs);
    }
  }

  Future<void> _loadState(
    SharedPreferences prefs,
    List<String> scopes,
    PlayerApiClient? client, {
    required bool allowRefresh,
    required int generation,
  }) async {
    await _removeLegacyCaches(prefs);
    if (_disposed || generation != _syncGeneration) return;

    final preferences = _readPreferences(prefs);
    final apiKeyScope = scopes.first;
    final apiKeySync = MusicDiscoveryApiKeySync(
      readLocalKey: () => _embeddedLastFmApiKey.isNotEmpty
          ? Future<String?>.value()
          : _apiKeyStore.readAndMigrate(
              prefs,
              readLegacyKey: _readLegacyApiKey ?? () async => null,
            ),
      writeLocalKey: (value) => _apiKeyStore.write(prefs, value),
      readHouseholdCache: () async {
        for (final scope in scopes) {
          final key = await _apiKeyStore.readHouseholdCache(prefs, scope);
          if (key != null) return key;
        }
        return null;
      },
      writeHouseholdCache: (value) =>
          _apiKeyStore.writeHouseholdCache(prefs, apiKeyScope, value),
      deleteHouseholdCache: () async {
        for (final scope in scopes) {
          await _apiKeyStore.deleteHouseholdCache(prefs, scope);
        }
      },
      fetchRemoteConfig: client?.fetchMusicDiscoveryApiKeyConfig,
      putRemoteKey: client?.putMusicDiscoveryApiKey,
      putRemoteKeyIfMissing: client == null
          ? null
          : (value) => client.putMusicDiscoveryApiKey(
                value,
                onlyIfMissing: true,
              ),
      deleteRemoteKey: client?.deleteMusicDiscoveryApiKey,
    );

    final apiKeyState = await apiKeySync.load(
      embeddedKey: _embeddedLastFmApiKey,
    );
    if (_disposed || generation != _syncGeneration) return;

    final cached = await _readSnapshotFor(prefs, preferences, scopes);
    if (_disposed || generation != _syncGeneration) return;

    final dismissed =
        (prefs.getStringList(_dismissedKey) ?? const <String>[]).toSet();
    final cachedWishlist = _readWishlistCache(prefs);

    _apiKeySync = apiKeySync;
    _apiKeyState = apiKeyState;
    _feedToken = apiKeyState.remoteConfig?.feedToken;
    _webhookUrl = apiKeyState.remoteConfig?.webhookUrl;
    _remoteCanManage = apiKeyState.remoteConfig?.canManage ?? false;
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _preferences = preferences;
    _rawSnapshot = cached;
    _wishlist = cachedWishlist;
    _applyLibraryFilter();
    _dismissedKeys = dismissed;
    _error = null;
    _errorKind = DiscoveryErrorKind.general;
    _coldStart = false;
    _loading = false;
    _initialized = true;
    _syncedClient = client;
    _syncedScope = apiKeyScope;
    notifyListeners();

    if (client != null) {
      unawaited(_syncRemoteWishlist(client, generation: generation));
    }
    if (allowRefresh && _enabled && hasApiKey && _isStale(cached)) {
      unawaited(refresh());
    }
  }

  Future<void> _clearAccountScopedState(SharedPreferences prefs) async {
    _refreshToken++;
    _refreshing = false;
    _rawSnapshot = null;
    _filteredSnapshot = null;
    _lastFilteredSongs = null;
    _coldStart = false;
    _error = null;
    _errorKind = DiscoveryErrorKind.general;
    _pendingRefreshAfterLibraryLoad = false;
    _dismissedKeys = <String>{};
    _wishlist = const <MusicRecommendation>[];
    _showSavedOnly = false;
    _feedToken = null;
    _webhookUrl = null;
    _remoteCanManage = false;
    _initialized = false;
    _syncedClient = null;
    _syncedScope = null;
    _closeLastFm();
    await _clearAllSnapshotCaches(prefs);
    await prefs.remove(_dismissedKey);
    await prefs.remove(_wishlistKey);
  }

  Future<void> _resetOnDisconnect(SharedPreferences prefs) async {
    _lastConnectedScope = null;
    _apiKeySync = null;
    _apiKeyState = const MusicDiscoveryApiKeySyncState(
      embeddedKey: null,
      localKey: null,
      householdKey: null,
      remoteConfig: null,
    );
    await _clearAccountScopedState(prefs);
    await prefs.remove(_lastScopeKey);
    _loading = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> clearCache() async {
    _refreshToken++;
    _refreshing = false;
    _rawSnapshot = null;
    _filteredSnapshot = null;
    _coldStart = false;
    _error = null;
    _errorKind = DiscoveryErrorKind.general;
    _pendingRefreshAfterLibraryLoad = false;
    final prefs = await SharedPreferences.getInstance();
    await _clearAllSnapshotCaches(prefs);
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh({bool force = false}) async {
    if ((!force && _refreshing) || !_enabled || !hasApiKey || _isOffline) {
      return;
    }
    final connection = _connection;
    final libraryController = _library;
    final statsController = _stats;
    if (connection == null ||
        libraryController == null ||
        statsController == null) {
      return;
    }

    if (libraryController.isLoading) {
      _pendingRefreshAfterLibraryLoad = true;
      _error =
          'Your library is still loading, so Ariami cannot safely remove owned music.';
      _errorKind = DiscoveryErrorKind.general;
      _coldStart = false;
      notifyListeners();
      return;
    }

    final token = ++_refreshToken;
    final preferences = _preferences;
    final library = libraryController.songs;
    final cacheScope = _apiKeyCacheScope(connection);

    _pendingRefreshAfterLibraryLoad = false;
    _refreshing = true;
    _error = null;
    _errorKind = DiscoveryErrorKind.general;
    _coldStart = false;
    notifyListeners();

    List<MusicRecommendationSeed> seeds;
    try {
      seeds = await _buildSeeds(statsController, preferences);
    } catch (_) {
      if (_disposed || token != _refreshToken) return;
      _refreshing = false;
      _error =
          'Ariami could not load your listening stats for ${preferences.tasteRange.title().toLowerCase()}. '
          'Try again when connected to your server.';
      _errorKind = DiscoveryErrorKind.general;
      notifyListeners();
      return;
    }

    if (_disposed || token != _refreshToken) return;
    if (seeds.isEmpty &&
        preferences.preferredTags.isEmpty &&
        !preferences.instrumentalOnly) {
      _refreshing = false;
      _coldStart = true;
      _error = null;
      notifyListeners();
      return;
    }

    final lastFm = _obtainLastFmClient(_effectiveApiKey);
    final service = MusicRecommendationService(
      lastFm: lastFm,
      musicBrainz: _musicBrainz,
    );
    try {
      final result = await service.discover(
        seeds: seeds,
        ownedTracks: library.map(
          (track) => OwnedMusicTrack(
            title: track.title,
            artist: track.artist,
            album: track.albumTitle,
            albumArtist: track.albumArtist,
          ),
        ),
        limit: preferences.resultLimit,
        mix: preferences.mix,
        preferredTags: preferences.preferredTags,
        libraryTags: splitMusicDiscoveryGenreTags(
          library.map((song) => song.genre),
        ),
        instrumentalOnly: preferences.instrumentalOnly,
      );
      if (_disposed || token != _refreshToken) return;
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || token != _refreshToken) return;
      await _writeSnapshot(prefs, cacheScope, preferences, result);
      if (_disposed || token != _refreshToken) return;
      _rawSnapshot = result;
      _applyLibraryFilter();
      _coldStart = false;
    } on LastFmRecommendationException catch (error) {
      if (_disposed || token != _refreshToken) return;
      _errorKind = error.isInvalidApiKey
          ? DiscoveryErrorKind.invalidApiKey
          : error.isRateLimited
              ? DiscoveryErrorKind.rateLimited
              : DiscoveryErrorKind.general;
      _error = error.isInvalidApiKey
          ? 'That Last.fm API key was rejected. Update it and try again.'
          : error.isRateLimited
              ? 'Last.fm is receiving too many requests. Try again shortly.'
              : error.message;
    } catch (_) {
      if (_disposed || token != _refreshToken) return;
      _errorKind = DiscoveryErrorKind.general;
      _error = 'Recommendations could not be refreshed.';
    } finally {
      if (!_disposed && token == _refreshToken) {
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> enableImmediately() async {
    const defaults = MusicDiscoveryPreferences();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferencesKey, jsonEncode(defaults.toJson()));
    await prefs.setBool(_enabledKey, true);
    if (_disposed) return;
    final connection = _connection;
    final scopes = connection == null
        ? const <String>[]
        : _identityScopes(
            connection,
            fallbackScope: prefs.getString(_lastScopeKey),
          );
    final cached = await _readSnapshotFor(prefs, defaults, scopes);
    if (_disposed) return;

    _refreshToken++;
    _refreshing = false;
    _enabled = true;
    _preferences = defaults;
    _rawSnapshot = cached;
    _applyLibraryFilter();
    _coldStart = false;
    _errorKind = DiscoveryErrorKind.general;
    _error = null;
    notifyListeners();
    if (_isStale(cached) && !_isOffline) {
      unawaited(refresh(force: true));
    }
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await _clearAllSnapshotCaches(prefs);
    if (_disposed) return;
    _refreshToken++;
    _refreshing = false;
    _enabled = false;
    _showSavedOnly = false;
    _rawSnapshot = null;
    _filteredSnapshot = null;
    _coldStart = false;
    _errorKind = DiscoveryErrorKind.general;
    _error = null;
    _pendingRefreshAfterLibraryLoad = false;
    _closeLastFm();
    notifyListeners();
  }

  Future<void> removeHouseholdKey() async {
    final sync = _apiKeySync;
    if (sync == null) return;
    final removal = await sync.removeHouseholdKey(_apiKeyState);
    if (_disposed) return;
    _apiKeyState = removal.state;
    if (!hasApiKey) {
      await _clearMissingKeyState();
    }
    _error = removal.syncSucceeded
        ? null
        : 'Ariami could not remove the shared API key. Try again when connected as the server owner.';
    notifyListeners();
  }

  Future<void> clearLocalKey() async {
    final prefs = await SharedPreferences.getInstance();
    await _apiKeyStore.delete(prefs);
    if (_disposed) return;
    _apiKeyState = MusicDiscoveryApiKeySyncState(
      embeddedKey: _apiKeyState.embeddedKey,
      localKey: null,
      householdKey: _apiKeyState.householdKey,
      remoteConfig: _apiKeyState.remoteConfig,
    );
    _error = null;
    _errorKind = DiscoveryErrorKind.general;
    if (!hasApiKey) {
      await _clearMissingKeyState();
    }
    notifyListeners();
  }

  Future<void> applySetupEnable({
    required String? personalKey,
    required MusicDiscoveryPreferences preferences,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String? syncWarning;
    if (!isEmbeddedApiKey && personalKey != null) {
      final sync = _apiKeySync;
      if (sync == null) return;
      try {
        final saved = await sync.save(_apiKeyState, personalKey);
        _apiKeyState = saved.state;
        if (saved.syncAttempted && !saved.syncSucceeded) {
          syncWarning = 'The API key was saved on this device, but Ariami '
              'could not share it with the server. Try saving again when connected.';
        }
      } catch (_) {
        if (_disposed) return;
        _errorKind = DiscoveryErrorKind.general;
        _error = 'Ariami could not save the API key locally. Try again.';
        notifyListeners();
        return;
      }
    }
    if (_disposed) return;
    await prefs.setBool(_enabledKey, true);
    final preferencesChanged = _preferences.cacheKey != preferences.cacheKey;
    final connection = _connection;
    final scopes = connection == null
        ? const <String>[]
        : _identityScopes(
            connection,
            fallbackScope: prefs.getString(_lastScopeKey),
          );
    final cached = preferencesChanged
        ? await _readSnapshotFor(prefs, preferences, scopes)
        : _rawSnapshot;
    await prefs.setString(_preferencesKey, jsonEncode(preferences.toJson()));
    if (_disposed) return;

    _refreshToken++;
    _refreshing = false;
    _enabled = true;
    _preferences = preferences;
    _rawSnapshot = cached;
    _applyLibraryFilter();
    _coldStart = false;
    _errorKind = DiscoveryErrorKind.general;
    _error = syncWarning;
    notifyListeners();

    if ((!preferencesChanged || _isStale(cached)) && !_isOffline) {
      unawaited(refresh(force: true));
    }
  }

  Future<void> applyPreferences(MusicDiscoveryPreferences next) async {
    final normalized = next.mix != MusicDiscoveryMix.tracks &&
            next.instrumentalOnly
        ? next.copyWith(instrumentalOnly: false)
        : next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _preferencesKey,
      jsonEncode(normalized.toJson()),
    );
    if (_disposed) return;
    final connection = _connection;
    final scopes = connection == null
        ? const <String>[]
        : _identityScopes(
            connection,
            fallbackScope: prefs.getString(_lastScopeKey),
          );
    final cached = await _readSnapshotFor(prefs, normalized, scopes);
    if (_disposed) return;

    _refreshToken++;
    _refreshing = false;
    _preferences = normalized;
    _rawSnapshot = cached;
    _applyLibraryFilter();
    _coldStart = false;
    _errorKind = DiscoveryErrorKind.general;
    _error = null;
    notifyListeners();

    if (_isStale(cached) && !_isOffline) {
      unawaited(refresh(force: true));
    }
  }

  void toggleShowSeeds() {
    _showSeeds = !_showSeeds;
    notifyListeners();
  }

  List<MusicRecommendation> visibleRecommendations(
    List<MusicRecommendation> items,
  ) {
    if (_dismissedKeys.isEmpty) return items;
    return items
        .where((item) => !_dismissedKeys.contains(_dismissKey(item)))
        .toList(growable: false);
  }

  Future<void> dismiss(MusicRecommendation item) async {
    final next = <String>{..._dismissedKeys, _dismissKey(item)};
    _dismissedKeys = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedKey, next.toList()..sort());
  }

  Future<void> clearDismissed() async {
    _dismissedKeys = <String>{};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dismissedKey);
  }

  void setShowSavedOnly(bool value) {
    if (_showSavedOnly == value) return;
    _showSavedOnly = value;
    notifyListeners();
  }

  Future<void> toggleWishlist(MusicRecommendation item) async {
    final key = item.identityKey;
    final wasSaved = isWishlisted(item);
    if (wasSaved) {
      _wishlist = _wishlist
          .where((entry) => entry.identityKey != key)
          .toList(growable: false);
      if (_wishlist.isEmpty) _showSavedOnly = false;
    } else {
      final saved =
          item.copyWith(savedAt: item.savedAt ?? DateTime.now().toUtc());
      _wishlist = <MusicRecommendation>[
        saved,
        ..._wishlist.where((entry) => entry.identityKey != key),
      ];
    }
    notifyListeners();
    await _persistWishlistCache();

    final client = _connection?.client;
    if (client == null || _isOffline) return;
    try {
      final response = wasSaved
          ? await client.removeMusicDiscoveryWishlistItem(key)
          : await client.addMusicDiscoveryWishlistItem(item);
      if (_disposed || isWishlisted(item) == wasSaved) return;
      _applyWishlistResponse(response);
      await _persistWishlistCache();
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  Future<String?> saveWebhookUrl(String? url) async {
    final client = _connection?.client;
    if (client == null || _isOffline) {
      return 'Connect to your server to update the wishlist webhook.';
    }
    try {
      final config = await client.putMusicDiscoveryWebhookUrl(url);
      if (_disposed) return null;
      _webhookUrl = config.webhookUrl;
      _feedToken = config.feedToken ?? _feedToken;
      _remoteCanManage = config.canManage;
      notifyListeners();
      return null;
    } on PlayerApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not save the wishlist webhook URL.';
    }
  }

  Future<void> _syncRemoteWishlist(
    PlayerApiClient client, {
    required int generation,
  }) async {
    try {
      final response = await client.fetchMusicDiscoveryWishlist();
      if (_disposed || generation != _syncGeneration) return;
      _applyWishlistResponse(response);
      await _persistWishlistCache();
      if (!_disposed && generation == _syncGeneration) notifyListeners();
    } catch (_) {}
  }

  void _applyWishlistResponse(Map<String, dynamic> response) {
    final rawItems = response['items'];
    if (rawItems is List<dynamic>) {
      final owned = _ownedIndexFor(_library?.songs ?? const <Track>[]);
      _wishlist = rawItems
          .whereType<Map<String, dynamic>>()
          .map(MusicRecommendation.fromJson)
          .where((item) =>
              item.name.trim().isNotEmpty &&
              item.lastFmUrl.hasScheme &&
              (owned.isEmpty || !owned.containsRecommendation(item)))
          .toList(growable: false);
      if (_wishlist.isEmpty) _showSavedOnly = false;
    }
    final token = (response['feedToken'] as String?)?.trim();
    if (token != null && token.isNotEmpty) _feedToken = token;
    if (response.containsKey('webhookUrl')) {
      final rawWebhook = (response['webhookUrl'] as String?)?.trim();
      _webhookUrl =
          rawWebhook == null || rawWebhook.isEmpty ? null : rawWebhook;
    }
    if (response['canManage'] is bool) {
      _remoteCanManage = response['canManage'] as bool;
    }
  }

  Future<void> _persistWishlistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_wishlist.isEmpty) {
        await prefs.remove(_wishlistKey);
      } else {
        await prefs.setString(
          _wishlistKey,
          jsonEncode(_wishlist.map((item) => item.toJson()).toList()),
        );
      }
    } catch (_) {}
  }

  static List<MusicRecommendation> _readWishlistCache(SharedPreferences prefs) {
    final raw = prefs.getString(_wishlistKey);
    if (raw == null || raw.isEmpty) return const <MusicRecommendation>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(MusicRecommendation.fromJson)
            .where((item) => item.name.trim().isNotEmpty && item.lastFmUrl.hasScheme)
            .toList(growable: false);
      }
    } catch (_) {}
    return const <MusicRecommendation>[];
  }

  Future<void> _clearMissingKeyState() async {
    _refreshToken++;
    _refreshing = false;
    _rawSnapshot = null;
    _filteredSnapshot = null;
    _coldStart = false;
    _pendingRefreshAfterLibraryLoad = false;
    _closeLastFm();
    final prefs = await SharedPreferences.getInstance();
    await _clearAllSnapshotCaches(prefs);
  }

  LastFmRecommendationClient _obtainLastFmClient(String apiKey) {
    final current = _lastFm;
    if (current != null && current.apiKey == apiKey) return current;
    current?.close();
    return _lastFm = LastFmRecommendationClient(apiKey: apiKey);
  }

  void _closeLastFm() {
    _lastFm?.close();
    _lastFm = null;
  }

  void _applyLibraryFilter() {
    final raw = _rawSnapshot;
    final songs = _library?.songs ?? const <Track>[];
    _lastFilteredSongs = songs;
    if (songs.isEmpty) {
      _filteredSnapshot = raw;
      return;
    }
    final owned = _ownedIndexFor(songs);
    if (_wishlist.isNotEmpty && !owned.isEmpty) {
      final nextWishlist = _wishlist
          .where((item) => !owned.containsRecommendation(item))
          .toList(growable: false);
      if (nextWishlist.length != _wishlist.length) {
        _wishlist = nextWishlist;
        if (_wishlist.isEmpty) _showSavedOnly = false;
        unawaited(_persistWishlistCache());
      }
    }
    if (raw == null || raw.recommendations.isEmpty) {
      _filteredSnapshot = raw;
      return;
    }
    final filtered = raw.recommendations
        .where((item) => !owned.containsRecommendation(item))
        .toList(growable: false);
    _filteredSnapshot = filtered.length == raw.recommendations.length
        ? raw
        : MusicRecommendationSnapshot(
            generatedAt: raw.generatedAt,
            recommendations: filtered,
            artistSeeds: raw.artistSeeds,
            trackSeeds: raw.trackSeeds,
          );
  }

  static OwnedMusicIndex _ownedIndexFor(Iterable<Track> songs) =>
      OwnedMusicIndex(
        songs.map(
          (track) => OwnedMusicTrack(
            title: track.title,
            artist: track.artist,
            album: track.albumTitle,
            albumArtist: track.albumArtist,
          ),
        ),
      );

  static String _dismissKey(MusicRecommendation item) => item.identityKey;

  static bool _isStale(MusicRecommendationSnapshot? snapshot) =>
      snapshot == null ||
      DateTime.now().toUtc().difference(snapshot.generatedAt) > _refreshAge;

  static Future<List<MusicRecommendationSeed>> _buildSeeds(
    ListeningStatsController controller,
    MusicDiscoveryPreferences preferences,
  ) async {
    final range = preferences.tasteRange;
    if (range.isAllTime) {
      final stats = controller.snapshot;
      return buildTasteSeeds(
        artists: stats.artists
            .map((item) => TasteSeedEntry.artist(item.name, item.listenedMs)),
        tracks: stats.songs.map(
          (item) => TasteSeedEntry.track(
            artist: item.songArtist ?? '',
            title: item.songTitle ?? '',
            listenedMs: item.listenedMs,
            lastPlayedMs: item.lastPlayedMs,
          ),
        ),
        depth: preferences.seedDepth,
      );
    }
    final bounds = range.bounds()!;
    final period = await controller.loadPeriodStats(
      fromDay: bounds.from,
      toDay: bounds.to,
      limit: 50,
    );
    if (period == null) throw StateError('period stats unavailable');
    return buildTasteSeeds(
      artists: period.artists.map(
        (item) => TasteSeedEntry.artist(
          item.artistDisplay ?? item.artistKey,
          item.listenedMs,
        ),
      ),
      tracks: period.songs.map(
        (item) => TasteSeedEntry.track(
          artist: item.songArtist ?? '',
          title: item.songTitle ?? '',
          listenedMs: item.listenedMs,
        ),
      ),
      depth: preferences.seedDepth,
    );
  }

  static String _apiKeyCacheScope(ConnectionController connection) =>
      '${connection.serverInfo?.stableKey ?? 'offline'}|'
      '${connection.username ?? 'guest'}';

  static List<String> _identityScopes(
    ConnectionController connection, {
    String? fallbackScope,
  }) {
    final user = connection.username ?? 'guest';
    final info = connection.serverInfo;
    if (info == null) {
      return <String>{
        if (fallbackScope != null && fallbackScope.endsWith('|$user'))
          fallbackScope,
        'offline|$user',
      }.toList(growable: false);
    }
    return <String>{
      '${info.stableKey}|$user',
      for (final alias in info.endpointAliases) '$alias|$user',
    }.toList(growable: false);
  }

  static String _entryKey(
    String scope,
    MusicDiscoveryPreferences preferences,
  ) =>
      '${base64Url.encode(utf8.encode(scope))}_${preferences.cacheKey}';

  static List<Map<String, dynamic>> _readLruEntries(SharedPreferences prefs) {
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final entries = decoded['entries'];
        if (entries is List) {
          return entries.whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (_) {
      unawaited(prefs.remove(_cacheKey));
    }
    return <Map<String, dynamic>>[];
  }

  static Future<void> _writeLruEntries(
    SharedPreferences prefs,
    List<Map<String, dynamic>> entries,
  ) async {
    if (entries.isEmpty) {
      await prefs.remove(_cacheKey);
      return;
    }
    await prefs.setString(
      _cacheKey,
      jsonEncode(<String, dynamic>{'entries': entries}),
    );
  }

  static Future<MusicRecommendationSnapshot?> _readSnapshotFor(
    SharedPreferences prefs,
    MusicDiscoveryPreferences preferences,
    List<String> scopes,
  ) async {
    if (scopes.isEmpty) return null;
    final entries = _readLruEntries(prefs);
    if (entries.isEmpty) return null;

    for (final scope in scopes) {
      final targetKey = _entryKey(scope, preferences);
      final index = entries.indexWhere((entry) => entry['key'] == targetKey);
      if (index == -1) continue;
      final matched = entries[index];
      final rawSnapshot = matched['snapshot'];
      if (rawSnapshot is Map<String, dynamic>) {
        try {
          final parsed = MusicRecommendationSnapshot.fromJson(rawSnapshot);
          if (index != entries.length - 1) {
            entries.removeAt(index);
            entries.add(matched);
            await _writeLruEntries(prefs, entries);
          }
          return parsed;
        } catch (_) {}
      }
      entries.removeAt(index);
      await _writeLruEntries(prefs, entries);
    }
    return null;
  }

  static Future<void> _writeSnapshot(
    SharedPreferences prefs,
    String scope,
    MusicDiscoveryPreferences preferences,
    MusicRecommendationSnapshot snapshot,
  ) async {
    final key = _entryKey(scope, preferences);
    final entries = _readLruEntries(prefs)
      ..removeWhere((entry) => entry['key'] == key);
    entries.add(<String, dynamic>{
      'key': key,
      'snapshot': snapshot.toJson(),
    });
    while (entries.length > _maxCacheEntries) {
      entries.removeAt(0);
    }
    await _writeLruEntries(prefs, entries);
  }

  static Future<void> _removeLegacyCaches(SharedPreferences prefs) async {
    for (final key in prefs.getKeys()) {
      if (_legacyCachePrefixes.any(key.startsWith)) {
        await prefs.remove(key);
      }
    }
  }

  static Future<void> _clearAllSnapshotCaches(SharedPreferences prefs) async {
    await prefs.remove(_cacheKey);
    await _removeLegacyCaches(prefs);
  }

  static MusicDiscoveryPreferences _readPreferences(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(prefs.getString(_preferencesKey) ?? '');
      if (decoded is Map<String, dynamic>) {
        return MusicDiscoveryPreferences.fromJson(decoded);
      }
    } catch (_) {}
    return const MusicDiscoveryPreferences();
  }

  @override
  void dispose() {
    _disposed = true;
    _connection?.removeListener(_onConnectionChanged);
    _library?.removeListener(_onLibraryChanged);
    _closeLastFm();
    _musicBrainz.close();
    super.dispose();
  }
}
