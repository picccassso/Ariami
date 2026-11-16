import 'dart:convert';

import 'package:http/http.dart' as http;

import 'music_recommendation_models.dart';

class LastFmRecommendationException implements Exception {
  const LastFmRecommendationException(this.message, {this.apiCode});

  final String message;
  final int? apiCode;

  bool get isInvalidApiKey => apiCode == 10 || apiCode == 26;
  bool get isRateLimited => apiCode == 29;

  /// Last.fm reports an unknown artist or track as code 6 ("The artist you
  /// supplied could not be found", "Track not found"). That is a fact about
  /// one seed, not about the request, so callers skip the seed rather than
  /// failing the whole run.
  bool get isNotFound => apiCode == 6;

  @override
  String toString() => message;
}

class LastFmRecommendationCandidate {
  const LastFmRecommendationCandidate({
    required this.kind,
    required this.name,
    required this.match,
    required this.url,
    this.artist,
    this.musicBrainzId,
    this.imageUrl,
  });

  final MusicRecommendationKind kind;
  final String name;
  final String? artist;
  final double match;
  final Uri url;
  final String? musicBrainzId;
  final Uri? imageUrl;
}

class LastFmTopAlbum {
  const LastFmTopAlbum({
    required this.name,
    required this.artist,
    required this.url,
    this.musicBrainzId,
    this.imageUrl,
  });

  final String name;
  final String artist;
  final Uri url;
  final String? musicBrainzId;
  final Uri? imageUrl;
}

class LastFmRecommendationMetadata {
  const LastFmRecommendationMetadata({
    this.imageUrl,
    this.tags = const <String>{},
  });

  final Uri? imageUrl;
  final Set<String> tags;
}

/// Small, unauthenticated Last.fm client for discovery and tag metadata.
class LastFmRecommendationClient {
  LastFmRecommendationClient({
    required this.apiKey,
    http.Client? httpClient,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 12),
    this.retryDelay,
    this.cacheTtl = const Duration(minutes: 15),
    this.maxCacheEntries = 256,
    DateTime Function()? clock,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        endpoint = endpoint ?? Uri.https('ws.audioscrobbler.com', '/2.0/'),
        _clock = clock ?? DateTime.now;

  static const int _maxRetries = 2;

  final String apiKey;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Uri endpoint;
  final Duration timeout;
  final Duration Function(int attempt)? retryDelay;
  final Duration cacheTtl;
  final int maxCacheEntries;
  final DateTime Function() _clock;
  final Map<String, _CachedResponse> _cache = <String, _CachedResponse>{};
  final Map<String, Future<Map<String, dynamic>>> _inFlight =
      <String, Future<Map<String, dynamic>>>{};

  Future<List<LastFmRecommendationCandidate>> similarArtists(
    String artist, {
    int limit = 12,
  }) async {
    final json = await _request(<String, String>{
      'method': 'artist.getsimilar',
      'artist': artist,
      'limit': '$limit',
    });
    final root = json['similarartists'];
    final rows = root is Map<String, dynamic> ? root['artist'] : null;
    return _asMaps(rows)
        .map(_parseArtist)
        .whereType<LastFmRecommendationCandidate>()
        .toList(growable: false);
  }

  Future<List<LastFmRecommendationCandidate>> similarTracks({
    required String artist,
    required String track,
    int limit = 12,
  }) async {
    final json = await _request(<String, String>{
      'method': 'track.getsimilar',
      'artist': artist,
      'track': track,
      'limit': '$limit',
    });
    final root = json['similartracks'];
    final rows = root is Map<String, dynamic> ? root['track'] : null;
    return _asMaps(rows)
        .map(_parseTrack)
        .whereType<LastFmRecommendationCandidate>()
        .toList(growable: false);
  }

  Future<List<LastFmRecommendationCandidate>> topTracksForTag(
    String tag, {
    int limit = 50,
  }) async {
    final json = await _request(<String, String>{
      'method': 'tag.gettoptracks',
      'tag': normalizeMusicDiscoveryTag(tag),
      'limit': '$limit',
    });
    final root = json['tracks'];
    final rows = root is Map<String, dynamic>
        ? _asMaps(root['track']).toList(growable: false)
        : const <Map<String, dynamic>>[];
    return <LastFmRecommendationCandidate>[
      for (var i = 0; i < rows.length; i++)
        if (_parseTrack(rows[i], fallbackMatch: _rankMatch(i, rows.length))
            case final candidate?)
          candidate,
    ];
  }

  Future<List<LastFmRecommendationCandidate>> topArtistsForTag(
    String tag, {
    int limit = 50,
  }) async {
    final json = await _request(<String, String>{
      'method': 'tag.gettopartists',
      'tag': normalizeMusicDiscoveryTag(tag),
      'limit': '$limit',
    });
    final root = json['topartists'];
    final rows = root is Map<String, dynamic>
        ? _asMaps(root['artist']).toList(growable: false)
        : const <Map<String, dynamic>>[];
    return <LastFmRecommendationCandidate>[
      for (var i = 0; i < rows.length; i++)
        if (_parseArtist(rows[i], fallbackMatch: _rankMatch(i, rows.length))
            case final candidate?)
          candidate,
    ];
  }

  Future<LastFmTopAlbum?> topAlbum(String artist) async =>
      (await topAlbums(artist, limit: 1)).firstOrNull;

  Future<List<LastFmTopAlbum>> topAlbums(
    String artist, {
    int limit = 5,
  }) async {
    // Last.fm currently replaces artist portraits with its generic placeholder.
    // Top albums give the recommendation a truthful visual identity with one
    // request instead of trying the consistently empty artist image first.
    final albumsJson = await _request(<String, String>{
      'method': 'artist.gettopalbums',
      'artist': artist,
      'limit': '$limit',
    });
    final albumsRoot = albumsJson['topalbums'];
    final albums = albumsRoot is Map<String, dynamic>
        ? _asMaps(albumsRoot['album'])
        : const <Map<String, dynamic>>[];
    return <LastFmTopAlbum>[
      for (final album in albums)
        if ((album['name'] as String? ?? '').trim() case final name
            when name.isNotEmpty)
          LastFmTopAlbum(
            name: name,
            artist: artist,
            url: _safeAlbumUrl(album['url'], artist: artist, album: name),
            musicBrainzId: _nonEmpty(album['mbid']),
            imageUrl: _imageUrl(album['image']),
          ),
    ];
  }

  Future<Uri?> artistImage(String artist) async =>
      (await topAlbum(artist))?.imageUrl;

  Future<LastFmRecommendationMetadata> artistMetadata(String artist) async {
    final json = await _request(<String, String>{
      'method': 'artist.getinfo',
      'artist': artist,
    });
    final root = json['artist'];
    if (root is! Map<String, dynamic>) {
      return const LastFmRecommendationMetadata();
    }
    return LastFmRecommendationMetadata(
      imageUrl: _imageUrl(root['image']),
      tags: _tags((root['tags'] as Map<String, dynamic>?)?['tag']),
    );
  }

  Future<LastFmRecommendationMetadata> trackMetadata({
    required String artist,
    required String track,
  }) async {
    final json = await _request(<String, String>{
      'method': 'track.getinfo',
      'artist': artist,
      'track': track,
    });
    final root = json['track'];
    if (root is! Map<String, dynamic>) {
      return const LastFmRecommendationMetadata();
    }
    final album = root['album'];
    final albumImage =
        album is Map<String, dynamic> ? _imageUrl(album['image']) : null;
    return LastFmRecommendationMetadata(
      imageUrl: albumImage ?? _imageUrl(root['image']),
      tags: _tags((root['toptags'] as Map<String, dynamic>?)?['tag']),
    );
  }

  Future<Uri?> trackImage({
    required String artist,
    required String track,
  }) async =>
      (await trackMetadata(artist: artist, track: track)).imageUrl;

  bool get _cacheEnabled =>
      maxCacheEntries > 0 && cacheTtl > Duration.zero;

  void clearCache() => _cache.clear();

  Future<Map<String, dynamic>> _request(Map<String, String> query) async {
    if (!_cacheEnabled) {
      return _requestWithRetry(query);
    }
    final key = _cacheKey(query);
    final cached = _cache[key];
    if (cached != null) {
      if (_clock().difference(cached.cachedAt) < cacheTtl) {
        _cache.remove(key);
        _cache[key] = cached;
        return cached.data;
      }
      _cache.remove(key);
    }
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _requestWithRetry(query).then((decoded) {
      _storeCache(key, decoded);
      return decoded;
    });
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<Map<String, dynamic>> _requestWithRetry(
    Map<String, String> query,
  ) async {
    final uri = endpoint.replace(queryParameters: <String, String>{
      ...endpoint.queryParameters,
      ...query,
      'api_key': apiKey.trim(),
      'format': 'json',
      'autocorrect': '1',
    });
    for (var attempt = 0; ; attempt++) {
      http.Response response;
      try {
        response = await _httpClient.get(uri).timeout(timeout);
      } catch (error) {
        throw const LastFmRecommendationException(
          'Could not reach Last.fm. Check your connection and try again.',
        );
      }
      final isTransientStatus =
          response.statusCode == 429 || response.statusCode == 503;
      Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        if (isTransientStatus && attempt < _maxRetries) {
          await _waitForRetry(attempt);
          continue;
        }
        if (response.statusCode == 429) {
          throw const LastFmRecommendationException(
            'Last.fm rate limit exceeded. Please try again in a moment.',
            apiCode: 29,
          );
        }
        if (response.statusCode == 503) {
          throw const LastFmRecommendationException(
            'Last.fm is temporarily unavailable. Please try again.',
          );
        }
        throw const LastFmRecommendationException(
          'Last.fm returned an unreadable response.',
        );
      }
      if (decoded is! Map<String, dynamic>) {
        if (isTransientStatus && attempt < _maxRetries) {
          await _waitForRetry(attempt);
          continue;
        }
        throw const LastFmRecommendationException(
          'Last.fm returned an unexpected response.',
        );
      }
      final apiCode = (decoded['error'] as num?)?.toInt();
      if ((isTransientStatus || apiCode == 29) && attempt < _maxRetries) {
        await _waitForRetry(attempt);
        continue;
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          apiCode != null) {
        throw LastFmRecommendationException(
          decoded['message'] as String? ??
              'Last.fm could not load recommendations.',
          apiCode: apiCode ?? (response.statusCode == 429 ? 29 : null),
        );
      }
      return decoded;
    }
  }

  Future<void> _waitForRetry(int attempt) async {
    final delay = (retryDelay ?? _defaultRetryDelay)(attempt);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }

  static Duration _defaultRetryDelay(int attempt) =>
      Duration(milliseconds: 500 * (1 << attempt));

  void _storeCache(String key, Map<String, dynamic> data) {
    if (!_cacheEnabled) return;
    _cache.remove(key);
    while (_cache.length >= maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CachedResponse(data: data, cachedAt: _clock());
  }

  String _cacheKey(Map<String, String> query) {
    final normalized = <String, String>{};
    void addNormalized(Map<String, String> source) {
      for (final entry in source.entries) {
        final key = entry.key.trim().toLowerCase();
        if (key.isEmpty || key == 'api_key') continue;
        normalized[key] = entry.value.trim().toLowerCase();
      }
    }

    addNormalized(endpoint.queryParameters);
    addNormalized(query);
    normalized['format'] = 'json';
    normalized['autocorrect'] = '1';

    final method = normalized.remove('method') ?? '';
    final keys = normalized.keys.toList()..sort();
    final buffer = StringBuffer(method);
    for (final key in keys) {
      buffer
        ..write('&')
        ..write(Uri.encodeQueryComponent(key))
        ..write('=')
        ..write(Uri.encodeQueryComponent(normalized[key]!));
    }
    return buffer.toString();
  }

  LastFmRecommendationCandidate? _parseArtist(
    Map<String, dynamic> json, {
    double? fallbackMatch,
  }) {
    final name = (json['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;
    return LastFmRecommendationCandidate(
      kind: MusicRecommendationKind.artist,
      name: name,
      match: json.containsKey('match')
          ? _match(json['match'])
          : fallbackMatch ?? 0,
      url: _safeUrl(json['url'], artist: name),
      musicBrainzId: _nonEmpty(json['mbid']),
      imageUrl: _imageUrl(json['image']),
    );
  }

  LastFmRecommendationCandidate? _parseTrack(
    Map<String, dynamic> json, {
    double? fallbackMatch,
  }) {
    final name = (json['name'] as String? ?? '').trim();
    final artistJson = json['artist'];
    final artist = artistJson is Map<String, dynamic>
        ? (artistJson['name'] as String? ?? '').trim()
        : (artistJson as String? ?? '').trim();
    if (name.isEmpty || artist.isEmpty) return null;
    return LastFmRecommendationCandidate(
      kind: MusicRecommendationKind.track,
      name: name,
      artist: artist,
      match: json.containsKey('match')
          ? _match(json['match'])
          : fallbackMatch ?? 0,
      url: _safeUrl(json['url'], artist: artist, track: name),
      musicBrainzId: _nonEmpty(json['mbid']),
      imageUrl: _imageUrl(json['image']),
    );
  }

  static Iterable<Map<String, dynamic>> _asMaps(Object? value) {
    if (value is Map<String, dynamic>) return <Map<String, dynamic>>[value];
    if (value is List<dynamic>) return value.whereType<Map<String, dynamic>>();
    return const <Map<String, dynamic>>[];
  }

  static double _match(Object? raw) {
    var value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
    if (value > 1 && value <= 100) value /= 100;
    return value.clamp(0, 1);
  }

  static double _rankMatch(int index, int total) =>
      total <= 1 ? 1 : 1 - (index / total) * 0.45;

  static String? _nonEmpty(Object? raw) {
    final value = raw is String ? raw.trim() : '';
    return value.isEmpty ? null : value;
  }

  static Set<String> _tags(Object? raw) => _asMaps(raw)
      .map((tag) => _nonEmpty(tag['name'])?.toLowerCase())
      .whereType<String>()
      .toSet();

  static Uri? _imageUrl(Object? raw) {
    const sizePriority = <String, int>{
      'small': 1,
      'medium': 2,
      'large': 3,
      'extralarge': 4,
      'mega': 5,
    };
    final images = _asMaps(raw).toList(growable: false)
      ..sort((a, b) => (sizePriority[b['size']] ?? 0)
          .compareTo(sizePriority[a['size']] ?? 0));
    for (final image in images) {
      final parsed = Uri.tryParse((image['#text'] as String? ?? '').trim());
      if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) continue;
      if (parsed.path.contains('2a96cbd8b46e442fc41c2b86b821562f')) {
        continue;
      }
      return parsed.scheme == 'http' ? parsed.replace(scheme: 'https') : parsed;
    }
    return null;
  }

  static Uri _safeUrl(Object? raw, {required String artist, String? track}) {
    final parsed = Uri.tryParse(raw is String ? raw : '');
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed.scheme == 'http' ? parsed.replace(scheme: 'https') : parsed;
    }
    return Uri.https(
      'www.last.fm',
      track == null
          ? '/music/${Uri.encodeComponent(artist)}'
          : '/music/${Uri.encodeComponent(artist)}/_/${Uri.encodeComponent(track)}',
    );
  }

  static Uri _safeAlbumUrl(
    Object? raw, {
    required String artist,
    required String album,
  }) {
    final parsed = Uri.tryParse(raw is String ? raw : '');
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed.scheme == 'http' ? parsed.replace(scheme: 'https') : parsed;
    }
    return Uri.https(
      'www.last.fm',
      '/music/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(album)}',
    );
  }

  void close() {
    _cache.clear();
    if (_ownsHttpClient) _httpClient.close();
  }
}

class _CachedResponse {
  const _CachedResponse({required this.data, required this.cachedAt});

  final Map<String, dynamic> data;
  final DateTime cachedAt;
}
