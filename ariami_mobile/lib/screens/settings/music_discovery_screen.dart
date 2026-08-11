import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/ariami_core.dart'
    show
        LastFmRecommendationClient,
        LastFmRecommendationException,
        MusicBrainzIdentityClient,
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
        buildTasteSeeds;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/api_models.dart';
import '../../services/api/api_client.dart';
import '../../services/api/connection_service.dart';
import '../../services/stats/account_stats_service.dart';
import '../../services/stats/period_stats_cache.dart';
import '../../services/stats/period_stats_loader.dart';
import '../../services/stats/streaming_stats_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';

const String _embeddedLastFmApiKey =
    String.fromEnvironment('ARIAMI_LASTFM_API_KEY');

class MusicDiscoveryScreen extends StatefulWidget {
  const MusicDiscoveryScreen({super.key});

  @override
  State<MusicDiscoveryScreen> createState() => _MusicDiscoveryScreenState();
}

class _MusicDiscoveryScreenState extends State<MusicDiscoveryScreen> {
  static const _apiKeyStorageKey = 'ariami_lastfm_api_key_v1';
  static const _enabledKey = 'mobile_music_discovery_enabled_v1';
  static const _preferencesKey = 'mobile_music_discovery_preferences_v1';
  static const _cachePrefix = 'mobile_music_discovery_cache_v6_';
  static const _legacyCachePrefixes = <String>[
    'mobile_music_discovery_cache_v1_',
    'mobile_music_discovery_cache_v2_',
    'mobile_music_discovery_cache_v3_',
    'mobile_music_discovery_cache_v4_',
    // v5 keyed the taste period as recent/allTime; ranges changed the format.
    'mobile_music_discovery_cache_v5_',
  ];
  static const _refreshAge = Duration(hours: 24);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final StreamingStatsService _stats = StreamingStatsService();
  final ConnectionService _connection = ConnectionService();
  final PeriodStatsCache _periodCache = PeriodStatsCache();
  late final PeriodStatsLoader _periodLoader;

  List<SongModel> _librarySongs = const <SongModel>[];
  List<AlbumModel> _libraryAlbums = const <AlbumModel>[];
  MusicRecommendationSnapshot? _snapshot;
  String? _storedApiKey;
  String? _error;
  bool _enabled = false;
  bool _libraryReady = false;
  bool _loading = true;
  bool _refreshing = false;
  MusicDiscoveryPreferences _preferences = const MusicDiscoveryPreferences();

  String get _effectiveApiKey => (_storedApiKey?.trim().isNotEmpty ?? false)
      ? _storedApiKey!.trim()
      : _embeddedLastFmApiKey.trim();

  bool get _hasApiKey => _effectiveApiKey.isNotEmpty;

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
    unawaited(_initialize());
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

  Future<void> _initialize() async {
    await _stats.initialize();
    unawaited(AccountStatsService().refreshSummary());
    final prefs = await SharedPreferences.getInstance();
    await _removeLegacyCaches(prefs);
    final preferences = _readPreferences(prefs);
    _preferences = preferences;
    final storedKeyFuture = _secureStorage.read(key: _apiKeyStorageKey);
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
    final storedKey = await storedKeyFuture;
    final rawCache = prefs.getString(_cacheKey);
    MusicRecommendationSnapshot? cached;
    if (rawCache != null) {
      try {
        final decoded = jsonDecode(rawCache);
        if (decoded is Map<String, dynamic>) {
          cached = MusicRecommendationSnapshot.fromJson(decoded);
        }
      } catch (_) {
        await prefs.remove(_cacheKey);
      }
    }
    if (!mounted) return;
    setState(() {
      _storedApiKey = storedKey;
      _enabled = prefs.getBool(_enabledKey) ?? false;
      _librarySongs = librarySongs;
      _libraryAlbums = libraryAlbums;
      _preferences = preferences;
      _libraryReady = libraryReady;
      _snapshot = cached;
      _loading = false;
    });
    final stale = cached == null ||
        DateTime.now().toUtc().difference(cached.generatedAt) > _refreshAge;
    if (_enabled && _hasApiKey && stale) unawaited(_refresh());
  }

  static Future<void> _removeLegacyCaches(SharedPreferences prefs) async {
    for (final key in prefs.getKeys()) {
      if (_legacyCachePrefixes.any(key.startsWith)) await prefs.remove(key);
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

  String get _cacheKey {
    final server = _connection.serverInfo;
    final identity =
        '${server?.publicOrigin ?? server?.lanServer ?? server?.server ?? 'offline'}|'
        '${_connection.userId ?? 'guest'}';
    return '$_cachePrefix${base64Url.encode(utf8.encode(identity))}_'
        '${_preferences.cacheKey}';
  }

  Future<void> _refresh() async {
    if (_refreshing || !_enabled || !_hasApiKey) return;
    if (!_libraryReady) {
      setState(() => _error =
          'Your library is not ready yet, so Ariami cannot safely remove owned music.');
      return;
    }
    final cacheKey = _cacheKey;
    List<MusicRecommendationSeed> seeds;
    try {
      seeds = await _buildSeeds();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Ariami could not load your listening stats for ${_preferences.tasteRange.title().toLowerCase()}. '
          'Try again when connected to your server.');
      return;
    }
    if (seeds.isEmpty) {
      setState(() => _error = _preferences.tasteRange.isAllTime
          ? 'Listen to a few songs first so Ariami can learn your taste.'
          : 'No listening was recorded in ${_preferences.tasteRange.title()}. '
              'Pick a wider taste period.');
      return;
    }
    setState(() {
      _refreshing = true;
      _error = null;
    });
    final service = MusicRecommendationService(
      lastFm: LastFmRecommendationClient(apiKey: _effectiveApiKey),
      musicBrainz: MusicBrainzIdentityClient(),
    );
    try {
      final result = await service.discover(
        seeds: seeds,
        ownedTracks: _librarySongs.map((song) {
          final album = _libraryAlbums
              .where((item) => item.id == song.albumId)
              .firstOrNull;
          return OwnedMusicTrack(
            title: song.title,
            artist: song.artist,
            album: album?.title,
            albumArtist: album?.artist,
          );
        }),
        limit: _preferences.resultLimit,
        mix: _preferences.mix,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(result.toJson()));
      if (!mounted) return;
      setState(() => _snapshot = result);
    } on LastFmRecommendationException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.isInvalidApiKey
            ? 'That Last.fm API key was rejected. Update it and try again.'
            : error.isRateLimited
                ? 'Last.fm is receiving too many requests. Try again shortly.'
                : error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Recommendations could not be refreshed.');
    } finally {
      service.close();
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Seeds for the selected taste range. All-time reads the local stats
  /// store; every calendar range goes through the shared period loader, which
  /// falls back to the cached range when offline and yields null when neither
  /// source has data.
  Future<List<MusicRecommendationSeed>> _buildSeeds() async {
    final depth = _preferences.seedDepth;
    final range = _preferences.tasteRange;
    if (range.isAllTime) {
      return buildTasteSeeds(
        artists: _stats.getTopArtists(limit: depth).map((item) =>
            TasteSeedEntry.artist(
                item.artistName, item.totalTime.inMilliseconds)),
        tracks: _stats.getTopSongs(limit: depth).map(
              (item) => TasteSeedEntry.track(
                artist: item.songArtist ?? '',
                title: item.songTitle ?? '',
                listenedMs: item.totalTime.inMilliseconds,
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

  Future<void> _showSetup() async {
    final controller = TextEditingController(text: _storedApiKey ?? '');
    var obscure = true;
    var selectedMix = _preferences.mix;
    var selectedLimit = _preferences.resultLimit;
    // Guard the dropdown's value-must-be-an-item contract against a stored
    // range the picker does not offer (an anchored one, or a future kind).
    var selectedRange = MusicDiscoveryPreferences.tasteRangeChoices
            .contains(_preferences.tasteRange)
        ? _preferences.tasteRange
        : StatsRange.all;
    var selectedDepth = _preferences.seedDepth;
    final result = await showDialog<_SetupResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Private music discovery'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ariami sends only a handful of favourite artist and track '
                  'names to Last.fm. Listening history, playlists, account '
                  'details, and your full library stay private.',
                ),
                const SizedBox(height: 14),
                if (_embeddedLastFmApiKey.isEmpty) ...[
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Last.fm API key',
                      helperText:
                          'Stored in this device’s secure credential store.',
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
                      setDialogState(() => selectedMix = value);
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
                const SizedBox(height: 10),
                DropdownButtonFormField<StatsRange>(
                  initialValue: selectedRange,
                  decoration: const InputDecoration(labelText: 'Taste from'),
                  items: MusicDiscoveryPreferences.tasteRangeChoices
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              MusicDiscoveryPreferences.tasteRangeLabel(value),
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
              onPressed: () {
                final key = _embeddedLastFmApiKey.isNotEmpty
                    ? _embeddedLastFmApiKey
                    : controller.text.trim();
                if (key.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  _SetupResult.enable(
                    controller.text.trim(),
                    MusicDiscoveryPreferences(
                      mix: selectedMix,
                      resultLimit: selectedLimit,
                      tasteRange: selectedRange,
                      seedDepth: selectedDepth,
                    ),
                  ),
                );
              },
              child: Text(_enabled ? 'Save' : 'Enable'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!result.enabled) {
      await prefs.setBool(_enabledKey, false);
      await prefs.remove(_cacheKey);
      if (_embeddedLastFmApiKey.isEmpty) {
        await _secureStorage.delete(key: _apiKeyStorageKey);
      }
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _snapshot = null;
        if (_embeddedLastFmApiKey.isEmpty) _storedApiKey = null;
      });
      return;
    }
    if (_embeddedLastFmApiKey.isEmpty) {
      await _secureStorage.write(
        key: _apiKeyStorageKey,
        value: result.apiKey,
      );
    }
    await prefs.setString(
      _preferencesKey,
      jsonEncode(result.preferences.toJson()),
    );
    await prefs.setBool(_enabledKey, true);
    if (!mounted) return;
    final preferencesChanged =
        _preferences.cacheKey != result.preferences.cacheKey;
    setState(() {
      _enabled = true;
      _preferences = result.preferences;
      if (preferencesChanged) _snapshot = null;
      if (_embeddedLastFmApiKey.isEmpty) _storedApiKey = result.apiKey;
    });
    unawaited(_refresh());
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
            onPressed: _showSetup,
            icon: const Icon(Icons.tune_rounded),
          ),
          if (_enabled)
            IconButton(
              tooltip: 'Refresh recommendations',
              onPressed: _refreshing ? null : _refresh,
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
    if (!_enabled || !_hasApiKey) return _buildOptIn();
    final snapshot = _snapshot;
    if (_refreshing && snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return MiniPlayerScrollPaddingBuilder(
      builder: (context, bottomPadding) => ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 24),
        children: [
          _DiscoveryIntro(snapshot: snapshot, preferences: _preferences),
          if (_error != null) _ErrorCard(message: _error!),
          if (snapshot == null || snapshot.recommendations.isEmpty)
            _EmptyDiscovery(onRefresh: _refresh)
          else ...[
            if (snapshot.tracks.isNotEmpty)
              _RecommendationGroup(
                title: 'TRACKS TO FIND',
                items: snapshot.tracks,
                onFind: _showFindLinks,
              ),
            if (snapshot.artists.isNotEmpty)
              _RecommendationGroup(
                title: 'ARTISTS TO EXPLORE',
                items: snapshot.artists,
                onFind: _showFindLinks,
              ),
            if (snapshot.albums.isNotEmpty)
              _RecommendationGroup(
                title: 'ALBUMS TO TRY',
                items: snapshot.albums,
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

  Widget _buildOptIn() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.explore_rounded,
                size: 58,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: 18),
              const Text(
                'Discover music from your Ariami listening',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'Ariami calculates favourites privately and sends only a few '
                'selected names. There is no scrobbling and no Last.fm account connection.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _showSetup,
                icon: const Icon(Icons.lock_outline_rounded),
                label: Text(_embeddedLastFmApiKey.isEmpty
                    ? 'Add API key and enable'
                    : 'Enable music discovery'),
              ),
            ],
          ),
        ),
      );
}

class _SetupResult {
  const _SetupResult.enable(this.apiKey, this.preferences) : enabled = true;
  const _SetupResult.disable()
      : enabled = false,
        apiKey = '',
        preferences = const MusicDiscoveryPreferences();

  final bool enabled;
  final String apiKey;
  final MusicDiscoveryPreferences preferences;
}

class _DiscoveryIntro extends StatelessWidget {
  const _DiscoveryIntro({required this.snapshot, required this.preferences});
  final MusicRecommendationSnapshot? snapshot;
  final MusicDiscoveryPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final count = snapshot == null
        ? 0
        : snapshot!.artistSeeds.length + snapshot!.trackSeeds.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recommended from your listening',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            count == 0
                ? 'New music based on what you actually play in Ariami.'
                : 'Using $count private taste seeds. Music you already own has been removed.',
          ),
          const SizedBox(height: 4),
          Text(
            _preferenceSummary(preferences),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RecommendationGroup extends StatelessWidget {
  const _RecommendationGroup({
    required this.title,
    required this.items,
    required this.onFind,
  });

  final String title;
  final List<MusicRecommendation> items;
  final ValueChanged<MusicRecommendation> onFind;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            for (final item in items)
              Card(
                margin: const EdgeInsets.only(bottom: 9),
                child: ListTile(
                  leading: CircleAvatar(
                    child: item.imageUrl == null
                        ? _recommendationIcon(item.kind)
                        : ClipOval(
                            child: Image.network(
                              item.imageUrl.toString(),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _recommendationIcon(item.kind),
                            ),
                          ),
                  ),
                  title: Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    <String>[
                      if (item.displaySubtitle != null) item.displaySubtitle!,
                      'Because you like ${item.sourceSeeds.take(2).join(' and ')}',
                    ].join('\n'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'Find on…',
                    onPressed: () => onFind(item),
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                ),
              ),
          ],
        ),
      );

  static Widget _recommendationIcon(MusicRecommendationKind kind) => Icon(
        switch (kind) {
          MusicRecommendationKind.track => Icons.music_note_rounded,
          MusicRecommendationKind.artist => Icons.person_search_rounded,
          MusicRecommendationKind.album => Icons.album_rounded,
        },
      );
}

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

String _preferenceSummary(MusicDiscoveryPreferences preferences) {
  final mix = switch (preferences.mix) {
    MusicDiscoveryMix.balanced => 'Balanced',
    MusicDiscoveryMix.tracks => 'Tracks',
    MusicDiscoveryMix.artists => 'Artists',
    MusicDiscoveryMix.albums => 'Albums',
  };
  return '$mix · ${preferences.resultLimit} max · '
      '${MusicDiscoveryPreferences.tasteRangeLabel(preferences.tasteRange)} · '
      'depth ${preferences.seedDepth}';
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        margin: const EdgeInsets.only(bottom: 14),
        child: ListTile(
          leading: const Icon(Icons.error_outline_rounded),
          title: Text(message),
        ),
      );
}

class _EmptyDiscovery extends StatelessWidget {
  const _EmptyDiscovery({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const Icon(Icons.travel_explore_rounded, size: 46),
            const SizedBox(height: 12),
            const Text('No unowned matches yet',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: onRefresh, child: const Text('Try again')),
          ],
        ),
      );
}
