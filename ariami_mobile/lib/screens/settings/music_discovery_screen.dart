import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/ariami_core.dart'
    show
        LastFmRecommendationClient,
        LastFmRecommendationException,
        MusicBrainzIdentityClient,
        MusicDiscoveryApiKeyConfig,
        MusicDiscoveryApiKeySync,
        MusicDiscoveryApiKeySyncState,
        MusicDiscoveryMix,
        MusicDiscoveryPreferences,
        MusicRecommendation,
        MusicRecommendationKind,
        MusicRecommendationSeed,
        MusicRecommendationService,
        MusicRecommendationSnapshot,
        OwnedMusicTrack,
        StatsRange,
        TasteSeedEntry,
        buildTasteSeeds,
        musicDiscoveryTagLabel,
        normalizeMusicDiscoveryTag,
        splitMusicDiscoveryGenreTags;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/api_models.dart';
import '../../services/api/api_client.dart';
import '../../services/api/connection_service.dart';
import '../../services/music_discovery_api_key_store.dart';
import '../../services/music_discovery_cache.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../services/stats/account_stats_service.dart';
import '../../services/stats/period_stats_cache.dart';
import '../../services/stats/period_stats_loader.dart';
import '../../services/stats/streaming_stats_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../main/library/library_controller.dart';
import 'music_discovery_widgets.dart';

const String _embeddedLastFmApiKey =
    String.fromEnvironment('ARIAMI_LASTFM_API_KEY');

enum _DiscoveryErrorKind { general, invalidApiKey, rateLimited }

class MusicDiscoveryScreen extends StatefulWidget {
  const MusicDiscoveryScreen({super.key});

  @override
  State<MusicDiscoveryScreen> createState() => _MusicDiscoveryScreenState();
}

class _MusicDiscoveryScreenState extends State<MusicDiscoveryScreen> {
  static const _enabledKey = 'mobile_music_discovery_enabled_v1';
  static const _preferencesKey = 'mobile_music_discovery_preferences_v1';
  static const _refreshAge = Duration(hours: 24);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final MusicDiscoveryApiKeyStore _apiKeyStore =
      const MusicDiscoveryApiKeyStore();
  final MusicDiscoveryCache _cache = const MusicDiscoveryCache();
  final StreamingStatsService _stats = StreamingStatsService();
  final ConnectionService _connection = ConnectionService();
  final OfflinePlaybackService _offline = OfflinePlaybackService();
  final LibraryController _library = LibraryController();
  final PeriodStatsCache _periodCache = PeriodStatsCache();
  final MusicBrainzIdentityClient _musicBrainz = MusicBrainzIdentityClient();
  late final PeriodStatsLoader _periodLoader;

  LastFmRecommendationClient? _lastFm;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<OfflineMode>? _offlineSub;

  List<SongModel> _librarySongs = const <SongModel>[];
  List<AlbumModel> _libraryAlbums = const <AlbumModel>[];
  MusicRecommendationSnapshot? _rawSnapshot;
  MusicRecommendationSnapshot? _snapshot;
  MusicDiscoveryApiKeySync? _apiKeySync;
  MusicDiscoveryApiKeySyncState _apiKeyState =
      const MusicDiscoveryApiKeySyncState(
    embeddedKey: null,
    localKey: null,
    householdKey: null,
    remoteConfig: null,
  );
  String? _error;
  _DiscoveryErrorKind _errorKind = _DiscoveryErrorKind.general;
  bool _coldStart = false;
  bool _enabled = false;
  bool _libraryReady = false;
  bool _loading = true;
  bool _refreshing = false;
  int _refreshToken = 0;
  Set<String> _dismissedKeys = <String>{};
  MusicDiscoveryPreferences _preferences = const MusicDiscoveryPreferences();

  String get _effectiveApiKey => _apiKeyState.effectiveKey ?? '';
  bool get _hasApiKey => _effectiveApiKey.isNotEmpty;
  bool get _hasLocalKey =>
      _embeddedLastFmApiKey.isEmpty && _apiKeyState.localKey != null;
  bool get _isOffline => _offline.isOffline || !_connection.isConnected;

  @override
  void initState() {
    super.initState();
    // Same loader the stats screen uses, so a taste range means exactly what
    // the stats tab shows for it — including the offline cache fallback.
    _periodLoader = PeriodStatsLoader(
      fetchDay: (date, limit) =>
          _requireClient().getListeningDay(date, limit: limit),
      fetchPeriod: (from, to, limit) =>
          _requireClient().getListeningPeriod(from: from, to: to, limit: limit),
      fetchArtists: (limit) =>
          _requireClient().getListeningArtists(limit: limit),
      readCached: (from, to) {
        final scope = _periodCacheScope;
        if (scope == null) return Future<Map<String, dynamic>?>.value();
        return _periodCache.read(scope: scope, from: from, to: to);
      },
      writeCached: (from, to, stats) {
        final scope = _periodCacheScope;
        if (scope == null) return Future<void>.value();
        return _periodCache.write(
          scope: scope,
          from: from,
          to: to,
          stats: stats,
        );
      },
    );
    _library.addListener(_onLibraryChanged);
    _connectionSub = _connection.connectionStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _offlineSub = _offline.offlineModeStream.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _library.removeListener(_onLibraryChanged);
    _connectionSub?.cancel();
    _offlineSub?.cancel();
    _closeLastFm();
    _musicBrainz.close();
    super.dispose();
  }

  void _onLibraryChanged() {
    if (!mounted) return;
    _applyOwnedFilter();
    setState(() {});
  }

  ApiClient _requireClient() {
    final client = _connection.apiClient;
    if (client == null) throw StateError('not connected');
    return client;
  }

  String? get _periodCacheScope => PeriodStatsCache.scopeFor(
        userId: _connection.userId,
        serverInfo: _connection.serverInfo,
      );

  String get _apiKeyCacheScope => MusicDiscoveryCache.scopeFor(
        serverInfo: _connection.serverInfo,
        userId: _connection.userId,
      );

  String get _legacyApiKeyCacheScope {
    final server = _connection.serverInfo;
    final identity = server?.publicOrigin ??
        server?.lanServer ??
        server?.tailscaleServer ??
        server?.server ??
        'offline';
    return '$identity|${_connection.userId ?? 'guest'}';
  }

  Future<void> _initialize() async {
    await _stats.initialize();
    unawaited(AccountStatsService().refreshSummary());
    final prefs = await SharedPreferences.getInstance();
    final preferences = _readPreferences(prefs);
    _preferences = preferences;
    final client = _connection.apiClient;
    final apiKeyScope = _apiKeyCacheScope;
    final legacyScope = _legacyApiKeyCacheScope;
    final apiKeySync = MusicDiscoveryApiKeySync(
      readLocalKey: () => _embeddedLastFmApiKey.isNotEmpty
          ? Future<String?>.value()
          : _apiKeyStore.readAndMigrate(
              prefs,
              readLegacyKey: () => _secureStorage.read(
                key: MusicDiscoveryApiKeyStore.key,
              ),
            ),
      writeLocalKey: (value) => _apiKeyStore.write(prefs, value),
      readHouseholdCache: () async =>
          await _apiKeyStore.readHouseholdCache(prefs, apiKeyScope) ??
          await _apiKeyStore.readHouseholdCache(prefs, legacyScope),
      writeHouseholdCache: (value) =>
          _apiKeyStore.writeHouseholdCache(prefs, apiKeyScope, value),
      deleteHouseholdCache: () async {
        await _apiKeyStore.deleteHouseholdCache(prefs, apiKeyScope);
        await _apiKeyStore.deleteHouseholdCache(prefs, legacyScope);
      },
      fetchRemoteConfig: client?.getMusicDiscoveryApiKeyConfig,
      putRemoteKey: client?.putMusicDiscoveryApiKey,
      putRemoteKeyIfMissing: client == null
          ? null
          : (value) => client.putMusicDiscoveryApiKey(
                value,
                onlyIfMissing: true,
              ),
      deleteRemoteKey: client?.deleteMusicDiscoveryApiKey,
    );
    final apiKeyStateFuture = apiKeySync.load(
      embeddedKey: _embeddedLastFmApiKey,
    );
    var librarySongs = const <SongModel>[];
    var libraryAlbums = const <AlbumModel>[];
    var libraryReady = false;
    try {
      final library = await _connection.libraryReadFacade.getLibraryBundle();
      librarySongs = library.songs;
      libraryAlbums = library.albums;
      libraryReady =
          !library.isPartialRead && library.syncHealth?.hasSyncFailure != true;
    } catch (_) {
      // Discovery remains usable; owned-library filtering retries next visit.
    }
    final apiKeyState = await apiKeyStateFuture;
    final cached = await _readCachedSnapshot(prefs, preferences);
    final dismissed = await _cache.readDismissed(prefs);
    if (!mounted) return;
    setState(() {
      _apiKeySync = apiKeySync;
      _apiKeyState = apiKeyState;
      _enabled = prefs.getBool(_enabledKey) ?? false;
      _librarySongs = librarySongs;
      _libraryAlbums = libraryAlbums;
      _preferences = preferences;
      _libraryReady = libraryReady;
      _rawSnapshot = cached;
      _applyOwnedFilter();
      _dismissedKeys = dismissed;
      _loading = false;
    });
    if (_enabled && _hasApiKey && _isStale(cached) && !_isOffline) {
      unawaited(_refresh());
    }
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

  static bool _isStale(MusicRecommendationSnapshot? snapshot) =>
      snapshot == null ||
      DateTime.now().toUtc().difference(snapshot.generatedAt) > _refreshAge;

  Future<MusicRecommendationSnapshot?> _readCachedSnapshot(
    SharedPreferences prefs,
    MusicDiscoveryPreferences preferences,
  ) =>
      _cache.readSnapshot(
        prefs,
        preferences: preferences,
        scopes: MusicDiscoveryCache.scopesFor(
          prefs,
          serverInfo: _connection.serverInfo,
          userId: _connection.userId,
        ),
      );

  Iterable<OwnedMusicTrack> _ownedTracks() {
    final controllerState = _library.state;
    final songs = _activeLibrarySongs;
    final albums = controllerState.albums.isNotEmpty
        ? controllerState.albums
        : _libraryAlbums;
    final albumsById = <String, AlbumModel>{
      for (final album in albums) album.id: album,
    };
    return songs.map((song) {
      final album = song.albumId == null ? null : albumsById[song.albumId!];
      return OwnedMusicTrack(
        title: song.title,
        artist: song.artist,
        album: album?.title,
        albumArtist: album?.artist,
      );
    });
  }

  List<SongModel> get _activeLibrarySongs {
    final controllerState = _library.state;
    if (controllerState.songs.isNotEmpty) return controllerState.songs;
    if (controllerState.isOfflineMode &&
        controllerState.offlineTracks.isNotEmpty) {
      return controllerState.offlineTracks;
    }
    return _librarySongs;
  }

  void _applyOwnedFilter() {
    final raw = _rawSnapshot;
    if (raw == null) {
      _snapshot = null;
      return;
    }
    _snapshot = MusicDiscoveryCache.filterOwnedRecommendations(
      raw,
      _ownedTracks(),
    );
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

  Future<void> _refresh({bool force = false}) async {
    if ((!force && _refreshing) || !_enabled || !_hasApiKey || _isOffline) {
      return;
    }
    if (!_libraryReady) {
      setState(() {
        _error =
            'Your library is not ready yet, so Ariami cannot safely remove owned music.';
        _errorKind = _DiscoveryErrorKind.general;
        _coldStart = false;
      });
      return;
    }
    final token = ++_refreshToken;
    final preferences = _preferences;
    final scope = _apiKeyCacheScope;
    final apiKey = _effectiveApiKey;
    setState(() {
      _refreshing = true;
      _error = null;
      _errorKind = _DiscoveryErrorKind.general;
      _coldStart = false;
    });

    List<MusicRecommendationSeed> seeds;
    try {
      seeds = await _buildSeeds(preferences);
    } catch (_) {
      if (!mounted || token != _refreshToken) return;
      setState(() {
        _refreshing = false;
        _error =
            'Ariami could not load your listening stats for ${preferences.tasteRange.title().toLowerCase()}. '
            'Try again when connected to your server.';
        _errorKind = _DiscoveryErrorKind.general;
      });
      return;
    }

    if (!mounted || token != _refreshToken) return;
    if (seeds.isEmpty &&
        preferences.preferredTags.isEmpty &&
        !preferences.instrumentalOnly) {
      setState(() {
        _refreshing = false;
        _coldStart = true;
        _error = null;
        _errorKind = _DiscoveryErrorKind.general;
      });
      return;
    }

    final service = MusicRecommendationService(
      lastFm: _obtainLastFmClient(apiKey),
      musicBrainz: _musicBrainz,
    );
    try {
      final ownedTracks = _ownedTracks().toList(growable: false);
      final libraryTags = splitMusicDiscoveryGenreTags(
        _activeLibrarySongs.map((song) => song.genre),
      );
      final result = await service.discover(
        seeds: seeds,
        ownedTracks: ownedTracks,
        limit: preferences.resultLimit,
        mix: preferences.mix,
        preferredTags: preferences.preferredTags,
        libraryTags: libraryTags,
        instrumentalOnly: preferences.instrumentalOnly,
      );
      if (!mounted || token != _refreshToken) return;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || token != _refreshToken) return;
      await _cache.writeSnapshot(
        prefs,
        scope: scope,
        preferences: preferences,
        snapshot: result,
      );
      if (!mounted || token != _refreshToken) return;
      setState(() {
        _rawSnapshot = result;
        _applyOwnedFilter();
        _coldStart = false;
      });
    } on LastFmRecommendationException catch (error) {
      if (!mounted || token != _refreshToken) return;
      setState(() {
        _errorKind = error.isInvalidApiKey
            ? _DiscoveryErrorKind.invalidApiKey
            : error.isRateLimited
                ? _DiscoveryErrorKind.rateLimited
                : _DiscoveryErrorKind.general;
        _error = error.isInvalidApiKey
            ? 'That Last.fm API key was rejected. Update it and try again.'
            : error.isRateLimited
                ? 'Last.fm is receiving too many requests. Try again shortly.'
                : error.message;
      });
    } catch (_) {
      if (!mounted || token != _refreshToken) return;
      setState(() {
        _errorKind = _DiscoveryErrorKind.general;
        _error = 'Recommendations could not be refreshed.';
      });
    } finally {
      if (mounted && token == _refreshToken) {
        setState(() => _refreshing = false);
      }
    }
  }

  /// Seeds for the selected taste range. All-time reads the local stats
  /// store; every calendar range goes through the shared period loader, which
  /// falls back to the cached range when offline and yields null when neither
  /// source has data.
  Future<List<MusicRecommendationSeed>> _buildSeeds(
    MusicDiscoveryPreferences preferences,
  ) async {
    final depth = preferences.seedDepth;
    final range = preferences.tasteRange;
    if (range.isAllTime) {
      return buildTasteSeeds(
        artists: _stats.getTopArtists().map(
              (item) => TasteSeedEntry.artist(
                item.artistName,
                item.totalTime.inMilliseconds,
                lastPlayedMs: item.lastPlayed?.millisecondsSinceEpoch,
              ),
            ),
        tracks: _stats.getTopSongs().map(
              (item) => TasteSeedEntry.track(
                artist: item.songArtist ?? '',
                title: item.songTitle ?? '',
                listenedMs: item.totalTime.inMilliseconds,
                lastPlayedMs: item.lastPlayed?.millisecondsSinceEpoch,
              ),
            ),
        depth: depth,
      );
    }
    final period = await _periodLoader.load(range, limit: 50);
    if (period == null) throw StateError('period stats unavailable');
    return buildTasteSeeds(
      artists: period.artists.map((item) => TasteSeedEntry.artist(
            item.artistDisplay ?? item.artistKey,
            item.listenedMs,
          )),
      tracks: period.songs.map(
        (item) => TasteSeedEntry.track(
          artist: item.songArtist ?? '',
          title: item.songTitle ?? '',
          listenedMs: item.listenedMs,
        ),
      ),
      depth: depth,
    );
  }

  Future<void> _enableImmediately() async {
    _refreshToken++;
    const defaults = MusicDiscoveryPreferences();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferencesKey, jsonEncode(defaults.toJson()));
    await prefs.setBool(_enabledKey, true);
    final cached = await _readCachedSnapshot(prefs, defaults);
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _enabled = true;
      _preferences = defaults;
      _rawSnapshot = cached;
      _applyOwnedFilter();
      _coldStart = false;
      _error = null;
      _errorKind = _DiscoveryErrorKind.general;
    });
    if (_isStale(cached) && !_isOffline) {
      unawaited(_refresh(force: true));
    }
  }

  Future<void> _applyPreferences(MusicDiscoveryPreferences next) async {
    _refreshToken++;
    final normalized =
        next.mix != MusicDiscoveryMix.tracks && next.instrumentalOnly
            ? next.copyWith(instrumentalOnly: false)
            : next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _preferencesKey,
      jsonEncode(normalized.toJson()),
    );
    final cached = await _readCachedSnapshot(prefs, normalized);
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _preferences = normalized;
      _rawSnapshot = cached;
      _applyOwnedFilter();
      _coldStart = false;
      _error = null;
      _errorKind = _DiscoveryErrorKind.general;
    });
    if (_isStale(cached) && !_isOffline) {
      unawaited(_refresh(force: true));
    }
  }

  Future<void> _clearMissingKeyState(SharedPreferences prefs) async {
    _refreshToken++;
    _refreshing = false;
    _closeLastFm();
    await MusicDiscoveryCache.clearAll(prefs);
  }

  Future<void> _showSetup() async {
    final needsPersonalKey = _embeddedLastFmApiKey.isEmpty;
    final controller =
        TextEditingController(text: _apiKeyState.effectiveKey ?? '');
    var obscure = true;
    var keyTouched = false;
    var selectedMix = _preferences.mix;
    var selectedLimit = _preferences.resultLimit;
    // Guard the dropdown's value-must-be-an-item contract against a stored
    // range the picker does not offer (an anchored one, or a future kind).
    var selectedRange = MusicDiscoveryPreferences.tasteRangeChoices
            .contains(_preferences.tasteRange)
        ? _preferences.tasteRange
        : StatsRange.all;
    var selectedDepth = _preferences.seedDepth;
    final selectedTags = <String>{..._preferences.preferredTags};
    final libraryTags = splitMusicDiscoveryGenreTags(
      _activeLibrarySongs.map((song) => song.genre),
    );
    var instrumentalOnly = _preferences.instrumentalOnly;
    final result = await showDialog<_SetupResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final trimmedKey = controller.text.trim();
          final keyTooLong = needsPersonalKey &&
              utf8.encode(trimmedKey).length >
                  MusicDiscoveryApiKeyConfig.maxApiKeyBytes;
          final keyMissing = needsPersonalKey && trimmedKey.isEmpty;
          final keyErrorText = keyTooLong
              ? 'API key must be at most ${MusicDiscoveryApiKeyConfig.maxApiKeyBytes} bytes.'
              : (keyMissing && keyTouched ? 'Enter a Last.fm API key.' : null);
          final canSubmit = !needsPersonalKey || (!keyMissing && !keyTooLong);
          return AlertDialog(
            title: const Text('Private music discovery'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ariami sends only your selected exploration tags and a '
                    'handful of favourite artist and track names to Last.fm. '
                    'Listening history, playlists, account details, and your '
                    'full library stay private.',
                  ),
                  const SizedBox(height: 14),
                  if (needsPersonalKey) ...[
                    TextField(
                      controller: controller,
                      obscureText: obscure,
                      readOnly: _apiKeyState.isHouseholdManaged &&
                          !_apiKeyState.canManageHousehold,
                      onChanged: (_) => setDialogState(() => keyTouched = true),
                      decoration: InputDecoration(
                        labelText: 'Last.fm API key',
                        errorText: keyErrorText,
                        helperText: _apiKeyState.isHouseholdManaged
                            ? _apiKeyState.canManageHousehold
                                ? 'Shared by your Ariami server with signed-in devices.'
                                : 'Synced from this Ariami server by its owner.'
                            : _apiKeyState.canManageHousehold
                                ? 'Saving shares this key with your signed-in Ariami devices.'
                                : 'Stored locally unless the server owner shares a key.',
                        suffixIcon: IconButton(
                          tooltip: obscure ? 'Show API key' : 'Hide API key',
                          onPressed: () =>
                              setDialogState(() => obscure = !obscure),
                          icon: Icon(obscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _open(
                        Uri.parse('https://www.last.fm/api/account/create'),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Get a personal API key'),
                    ),
                    Text(
                      'A Last.fm developer account is only needed to obtain the '
                      'key; Ariami never signs into it.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if ((_apiKeyState.canManageHousehold &&
                            _apiKeyState.isHouseholdManaged) ||
                        _hasLocalKey)
                      Wrap(
                        spacing: 8,
                        children: [
                          if (_apiKeyState.canManageHousehold &&
                              _apiKeyState.isHouseholdManaged)
                            TextButton.icon(
                              onPressed: () => Navigator.pop(
                                dialogContext,
                                const _SetupResult.removeHouseholdKey(),
                              ),
                              icon: const Icon(Icons.link_off_rounded, size: 16),
                              label: const Text('Remove shared key'),
                            ),
                          if (_hasLocalKey)
                            TextButton.icon(
                              onPressed: () => Navigator.pop(
                                dialogContext,
                                const _SetupResult.clearLocalKey(),
                              ),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                              ),
                              label: const Text('Clear local key'),
                            ),
                        ],
                      ),
                  ] else
                    const Text(
                      'This build includes an Ariami Last.fm API key. Enabling '
                      'discovery is still your choice.',
                    ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Recommendations',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<MusicDiscoveryMix>(
                    key: ValueKey(selectedMix),
                    initialValue: selectedMix,
                    decoration: const InputDecoration(labelText: 'Show'),
                    items: MusicDiscoveryMix.values
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_mixLabel(value)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          selectedMix = value;
                          if (value != MusicDiscoveryMix.tracks) {
                            instrumentalOnly = false;
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: selectedLimit,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    items: const <DropdownMenuItem<int>>[
                      DropdownMenuItem(
                          value: 12, child: Text('Compact · up to 12')),
                      DropdownMenuItem(
                          value: 24, child: Text('Standard · up to 24')),
                      DropdownMenuItem(value: 36, child: Text('More · up to 36')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedLimit = value);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text('Refine suggestions',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Instrumental only'),
                    subtitle: const Text(
                      "Explores Last.fm's instrumental pool and keeps only "
                      'tracks with explicit instrumental evidence.',
                    ),
                    value: instrumentalOnly,
                    onChanged: (value) => setDialogState(() {
                      instrumentalOnly = value;
                      if (value) selectedMix = MusicDiscoveryMix.tracks;
                    }),
                  ),
                  Text(
                    'Explore tags',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  _MusicTagPicker(
                    selectedTags: selectedTags,
                    libraryTags: libraryTags,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tags choose the Last.fm music Ariami explores. Multiple '
                    'tags broaden the results; Instrumental remains an extra '
                    'requirement. Library genres gently rank matching results '
                    'and appear here as suggestions; they never limit you.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<StatsRange>(
                    initialValue: selectedRange,
                    decoration: const InputDecoration(labelText: 'Taste from'),
                    items: MusicDiscoveryPreferences.tasteRangeChoices
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                MusicDiscoveryPreferences.tasteRangeLabel(
                                  value,
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedRange = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: selectedDepth,
                    decoration: const InputDecoration(labelText: 'Taste depth'),
                    items: MusicDiscoveryPreferences.seedDepthChoices
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_depthLabel(value)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedDepth = value);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Deeper reaches further down your favourites, so results '
                    'get broader and refreshing takes longer.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No Last.fm account is connected and Ariami never scrobbles. '
                    'Last.fm and MusicBrainz terms still apply.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              if (_enabled)
                TextButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    const _SetupResult.disable(),
                  ),
                  child: const Text('Disable'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canSubmit
                    ? () => Navigator.pop(
                          dialogContext,
                          _SetupResult.enable(
                            needsPersonalKey ? trimmedKey : null,
                            MusicDiscoveryPreferences(
                              mix: selectedMix,
                              resultLimit: selectedLimit,
                              tasteRange: selectedRange,
                              seedDepth: selectedDepth,
                              preferredTags: selectedTags,
                              instrumentalOnly: instrumentalOnly,
                            ),
                          ),
                        )
                    : null,
                child: Text(_enabled ? 'Save' : 'Enable'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();
    switch (result.action) {
      case _SetupAction.removeHouseholdKey:
        final sync = _apiKeySync;
        if (sync == null) return;
        final removal = await sync.removeHouseholdKey(_apiKeyState);
        if (!mounted) return;
        final missingKey = (removal.state.effectiveKey ?? '').isEmpty;
        if (missingKey) {
          await _clearMissingKeyState(prefs);
          if (!mounted) return;
        }
        setState(() {
          _apiKeyState = removal.state;
          if (missingKey) {
            _rawSnapshot = null;
            _snapshot = null;
            _coldStart = false;
          }
          _error = removal.syncSucceeded
              ? null
              : 'Ariami could not remove the shared API key. Try again when connected as the server owner.';
          _errorKind = _DiscoveryErrorKind.general;
        });
        return;
      case _SetupAction.clearLocalKey:
        await _apiKeyStore.delete(prefs);
        if (!mounted) return;
        final nextState = MusicDiscoveryApiKeySyncState(
          embeddedKey: _apiKeyState.embeddedKey,
          localKey: null,
          householdKey: _apiKeyState.householdKey,
          remoteConfig: _apiKeyState.remoteConfig,
        );
        final missingKey = (nextState.effectiveKey ?? '').isEmpty;
        if (missingKey) {
          await _clearMissingKeyState(prefs);
          if (!mounted) return;
        }
        setState(() {
          _apiKeyState = nextState;
          if (missingKey) {
            _rawSnapshot = null;
            _snapshot = null;
            _coldStart = false;
          }
          _error = null;
          _errorKind = _DiscoveryErrorKind.general;
        });
        return;
      case _SetupAction.disable:
        _refreshToken++;
        _closeLastFm();
        await prefs.setBool(_enabledKey, false);
        await MusicDiscoveryCache.clearAll(prefs);
        if (!mounted) return;
        setState(() {
          _refreshing = false;
          _enabled = false;
          _rawSnapshot = null;
          _snapshot = null;
          _coldStart = false;
          _error = null;
          _errorKind = _DiscoveryErrorKind.general;
        });
        return;
      case _SetupAction.enable:
        _refreshToken++;
        String? syncWarning;
        if (needsPersonalKey && result.apiKey != null) {
          try {
            final saved = await _apiKeySync!.save(_apiKeyState, result.apiKey!);
            _apiKeyState = saved.state;
            if (saved.syncAttempted && !saved.syncSucceeded) {
              syncWarning = 'The API key was saved on this device, but Ariami '
                  'could not share it with the server. Try saving again when connected.';
            }
          } catch (_) {
            if (!mounted) return;
            setState(() {
              _errorKind = _DiscoveryErrorKind.general;
              _error = 'Ariami could not save the API key locally. Try again.';
            });
            return;
          }
        }
        await prefs.setString(
          _preferencesKey,
          jsonEncode(result.preferences.toJson()),
        );
        await prefs.setBool(_enabledKey, true);
        final preferencesChanged =
            _preferences.cacheKey != result.preferences.cacheKey;
        final cached = preferencesChanged
            ? await _readCachedSnapshot(prefs, result.preferences)
            : _rawSnapshot;
        if (!mounted) return;
        setState(() {
          _refreshing = false;
          _enabled = true;
          _preferences = result.preferences;
          _rawSnapshot = cached;
          _applyOwnedFilter();
          _coldStart = false;
          _error = syncWarning;
          _errorKind = _DiscoveryErrorKind.general;
        });
        if ((!preferencesChanged || _isStale(cached)) && !_isOffline) {
          unawaited(_refresh(force: true));
        }
    }
  }

  List<MusicRecommendation> _visibleRecommendations(
    List<MusicRecommendation> items,
  ) {
    if (_dismissedKeys.isEmpty) return items;
    return items
        .where(
          (item) => !_dismissedKeys.contains(MusicDiscoveryCache.keyFor(item)),
        )
        .toList(growable: false);
  }

  Future<void> _dismiss(MusicRecommendation item) async {
    final key = MusicDiscoveryCache.keyFor(item);
    setState(() => _dismissedKeys = <String>{..._dismissedKeys, key});
    final prefs = await SharedPreferences.getInstance();
    final updated = await _cache.dismiss(prefs, item);
    if (mounted) setState(() => _dismissedKeys = updated);
  }

  Future<void> _restoreDismissed() async {
    setState(() => _dismissedKeys = <String>{});
    final prefs = await SharedPreferences.getInstance();
    await _cache.restoreAll(prefs);
  }

  String? _matchedLibraryArtist(MusicRecommendation item) {
    final candidate = (item.kind == MusicRecommendationKind.artist
            ? item.name
            : item.artist)
        ?.trim();
    if (candidate == null || candidate.isEmpty) return null;
    if (_library.artistTracks(candidate).isEmpty &&
        _library.artistAlbums(candidate).isEmpty) {
      return null;
    }
    return candidate;
  }

  void _openArtist(String artistName) {
    Navigator.of(context).pushNamed('/artist', arguments: artistName);
  }

  static List<String> _quickStartTags(Iterable<String?> genres) {
    final library = splitMusicDiscoveryGenreTags(genres).toList()..sort();
    return <String>{
      ...library,
      ...MusicDiscoveryPreferences.commonTags,
    }.take(8).toList(growable: false);
  }

  Future<void> _open(Uri uri) async {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open that link.')),
    );
  }

  void _showFindLinks(MusicRecommendation item) {
    final musicBrainz = item.musicBrainzUrl;
    showMiniPlayerAwareBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(item.displayTitle),
              subtitle: item.displaySubtitle == null
                  ? null
                  : Text(item.displaySubtitle!),
            ),
            ListTile(
              leading: const Icon(Icons.radio_rounded),
              title: const Text('Last.fm'),
              onTap: () {
                Navigator.pop(sheetContext);
                _open(item.lastFmUrl);
              },
            ),
            if (musicBrainz != null)
              ListTile(
                leading: const Icon(Icons.fingerprint_rounded),
                title: const Text('MusicBrainz'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _open(musicBrainz);
                },
              ),
            ListTile(
              leading: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('YouTube Music'),
              onTap: () {
                Navigator.pop(sheetContext);
                _open(item.youtubeMusicUrl);
              },
            ),
            ListTile(
              leading: const Icon(Icons.storefront_rounded),
              title: const Text('Bandcamp'),
              onTap: () {
                Navigator.pop(sheetContext);
                _open(item.bandcampUrl);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Discovery preferences',
            onPressed: _loading ? null : _showSetup,
            icon: const Icon(Icons.tune_rounded),
          ),
          if (_enabled)
            IconButton(
              tooltip: 'Refresh recommendations',
              onPressed:
                  _refreshing || _isOffline ? null : () => unawaited(_refresh()),
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: ContentWidthLimiter(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_enabled || !_hasApiKey) {
      return DiscoveryOptInView(
        hasApiKey: _hasApiKey,
        error: _error,
        onEnableImmediately: () => unawaited(_enableImmediately()),
        onOpenSetup: () => unawaited(_showSetup()),
      );
    }

    final isOffline = _isOffline;
    final snapshot = _snapshot;
    final tracks = snapshot == null
        ? const <MusicRecommendation>[]
        : _visibleRecommendations(snapshot.tracks);
    final artists = snapshot == null
        ? const <MusicRecommendation>[]
        : _visibleRecommendations(snapshot.artists);
    final albums = snapshot == null
        ? const <MusicRecommendation>[]
        : _visibleRecommendations(snapshot.albums);
    final hasVisible =
        tracks.isNotEmpty || artists.isNotEmpty || albums.isNotEmpty;
    final allDismissed = snapshot != null &&
        snapshot.recommendations.isNotEmpty &&
        !hasVisible;

    final (errorActionLabel, errorAction) = switch (_errorKind) {
      _DiscoveryErrorKind.invalidApiKey => (
          'Update API key',
          () => unawaited(_showSetup()),
        ),
      _DiscoveryErrorKind.rateLimited || _DiscoveryErrorKind.general => (
          isOffline ? null : 'Retry',
          isOffline ? null : () => unawaited(_refresh(force: true)),
        ),
    };

    return MiniPlayerScrollPaddingBuilder(
      builder: (context, bottomPadding) => ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 24),
        children: [
          DiscoveryHeader(
            snapshotSeedCount: snapshot == null
                ? 0
                : snapshot.artistSeeds.length + snapshot.trackSeeds.length,
            snapshotGeneratedAt: snapshot?.generatedAt,
            preferences: _preferences,
            dismissedCount: _dismissedKeys.length,
            onMixSelected: (mix) =>
                unawaited(_applyPreferences(_preferences.copyWith(mix: mix))),
            onClearInstrumental: () => unawaited(
              _applyPreferences(_preferences.copyWith(instrumentalOnly: false)),
            ),
            onRemoveTag: (tag) {
              final nextTags = <String>{..._preferences.preferredTags}
                ..remove(tag);
              unawaited(
                _applyPreferences(
                  _preferences.copyWith(preferredTags: nextTags),
                ),
              );
            },
            onOpenSetup: () => unawaited(_showSetup()),
            onRestoreDismissed: () => unawaited(_restoreDismissed()),
          ),
          if (isOffline && snapshot != null)
            const DiscoveryNoticeBanner(
              icon: Icons.cloud_off_rounded,
              message: 'Offline — showing cached results.',
            ),
          if (_error != null)
            DiscoveryErrorCard(
              message: _error!,
              actionLabel: errorActionLabel,
              onAction: errorAction,
            ),
          if (_refreshing && snapshot == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null && snapshot == null)
            const SizedBox.shrink()
          else if (isOffline && snapshot == null)
            const DiscoveryOfflineView()
          else if (_coldStart && snapshot == null)
            DiscoveryColdStartView(
              isAllTime: _preferences.tasteRange.isAllTime,
              rangeTitle: _preferences.tasteRange.title(),
              quickTags: _quickStartTags(
                _activeLibrarySongs.map((song) => song.genre),
              ),
              onSelectTag: (tag) => unawaited(
                _applyPreferences(
                  _preferences.copyWith(
                    preferredTags: <String>{
                      ..._preferences.preferredTags,
                      tag,
                    },
                  ),
                ),
              ),
              onUseAllTime: () => unawaited(
                _applyPreferences(
                  _preferences.copyWith(tasteRange: StatsRange.all),
                ),
              ),
              onBrowseLibrary: () => Navigator.of(context).maybePop(),
            )
          else if (snapshot == null || !hasVisible)
            DiscoveryEmptyView(
              onRefresh: () => unawaited(_refresh(force: true)),
              onAdjustFilters: () => unawaited(_showSetup()),
              onRestoreDismissed:
                  allDismissed ? () => unawaited(_restoreDismissed()) : null,
            )
          else ...[
            if (tracks.isNotEmpty)
              DiscoveryRecommendationGroup(
                title: 'Tracks to find',
                items: tracks,
                matchedArtistFor: _matchedLibraryArtist,
                onOpenArtist: _openArtist,
                onDismiss: (item) => unawaited(_dismiss(item)),
                onFind: _showFindLinks,
              ),
            if (artists.isNotEmpty)
              DiscoveryRecommendationGroup(
                title: 'Artists to explore',
                items: artists,
                matchedArtistFor: _matchedLibraryArtist,
                onOpenArtist: _openArtist,
                onDismiss: (item) => unawaited(_dismiss(item)),
                onFind: _showFindLinks,
              ),
            if (albums.isNotEmpty)
              DiscoveryRecommendationGroup(
                title: 'Albums to try',
                items: albums,
                matchedArtistFor: _matchedLibraryArtist,
                onOpenArtist: _openArtist,
                onDismiss: (item) => unawaited(_dismiss(item)),
                onFind: _showFindLinks,
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  const Text(
                    'Ranked by Last.fm · identities assisted by MusicBrainz · '
                    'full listening history stays in Ariami',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () =>
                            _open(Uri.parse('https://www.last.fm')),
                        child: const Text('Powered by Last.fm'),
                      ),
                      TextButton(
                        onPressed: () =>
                            _open(Uri.parse('https://musicbrainz.org')),
                        child: const Text('MusicBrainz'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SetupResult {
  const _SetupResult.enable(this.apiKey, this.preferences)
      : action = _SetupAction.enable;
  const _SetupResult.disable()
      : action = _SetupAction.disable,
        apiKey = null,
        preferences = const MusicDiscoveryPreferences();
  const _SetupResult.removeHouseholdKey()
      : action = _SetupAction.removeHouseholdKey,
        apiKey = null,
        preferences = const MusicDiscoveryPreferences();
  const _SetupResult.clearLocalKey()
      : action = _SetupAction.clearLocalKey,
        apiKey = null,
        preferences = const MusicDiscoveryPreferences();

  final _SetupAction action;
  final String? apiKey;
  final MusicDiscoveryPreferences preferences;
}

enum _SetupAction { enable, disable, removeHouseholdKey, clearLocalKey }

String _mixLabel(MusicDiscoveryMix mix) => switch (mix) {
      MusicDiscoveryMix.balanced => 'Balanced · tracks and artists',
      MusicDiscoveryMix.tracks => 'Tracks only',
      MusicDiscoveryMix.artists => 'Artists only',
      MusicDiscoveryMix.albums => 'Albums only',
    };

String _depthLabel(int depth) => switch (depth) {
      3 => 'Focused · top 3 artists and tracks',
      6 => 'Wider · top 6 artists and tracks',
      _ => 'Deepest · top $depth artists and tracks',
    };

class _MusicTagPicker extends StatefulWidget {
  const _MusicTagPicker({
    required this.selectedTags,
    required this.libraryTags,
  });

  final Set<String> selectedTags;
  final Set<String> libraryTags;

  @override
  State<_MusicTagPicker> createState() => _MusicTagPickerState();
}

class _MusicTagPickerState extends State<_MusicTagPicker> {
  final _controller = TextEditingController();
  String _query = '';

  void _add(String value) {
    final tag = normalizeMusicDiscoveryTag(value);
    if (tag.isEmpty) return;
    setState(() {
      widget.selectedTags.add(tag);
      _controller.clear();
      _query = '';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matching = <String>{
      ...widget.libraryTags,
      ...MusicDiscoveryPreferences.commonTags,
    }
        .where((tag) =>
            !widget.selectedTags.contains(tag) &&
            (_query.isEmpty || tag.contains(_query)))
        .toList()
      ..sort();
    final suggestions = matching.take(18).toList(growable: false);
    final selected = widget.selectedTags.toList()..sort();
    final entered = normalizeMusicDiscoveryTag(_controller.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Search or add any Last.fm tag',
            hintText: 'For example: fusion',
            suffixIcon: IconButton(
              tooltip: 'Add tag',
              onPressed: entered.isEmpty ? null : () => _add(entered),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
          onChanged: (value) => setState(
            () => _query = normalizeMusicDiscoveryTag(value),
          ),
          onSubmitted: _add,
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: selected
                .map((tag) => InputChip(
                      label: Text(musicDiscoveryTagLabel(tag)),
                      onDeleted: () => setState(
                        () => widget.selectedTags.remove(tag),
                      ),
                    ))
                .toList(),
          ),
        ],
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: suggestions
                .map((tag) => ActionChip(
                      avatar: widget.libraryTags.contains(tag)
                          ? const Icon(Icons.library_music_rounded, size: 16)
                          : null,
                      label: Text(musicDiscoveryTagLabel(tag)),
                      tooltip: widget.libraryTags.contains(tag)
                          ? 'Found in your library metadata'
                          : 'Common Last.fm tag',
                      onPressed: () => _add(tag),
                    ))
                .toList(),
          ),
        ] else if (_query.isNotEmpty && !widget.selectedTags.contains(_query)) ...[
          const SizedBox(height: 8),
          Text(
            'Tap + or press Done to add "$_query"',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
