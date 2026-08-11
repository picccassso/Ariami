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

/// Small, unauthenticated Last.fm client for the two similarity endpoints.
class LastFmRecommendationClient {
  LastFmRecommendationClient({
    required this.apiKey,
    http.Client? httpClient,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 12),
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        endpoint = endpoint ?? Uri.https('ws.audioscrobbler.com', '/2.0/');

  final String apiKey;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Uri endpoint;
  final Duration timeout;

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

  Future<LastFmTopAlbum?> topAlbum(String artist) async {
    // Last.fm currently replaces artist portraits with its generic placeholder.
    // A top album gives the recommendation a truthful visual identity with one
    // request instead of trying the consistently empty artist image first.
    final albumsJson = await _request(<String, String>{
      'method': 'artist.gettopalbums',
      'artist': artist,
      'limit': '1',
    });
    final albumsRoot = albumsJson['topalbums'];
    final albums = albumsRoot is Map<String, dynamic>
        ? _asMaps(albumsRoot['album'])
        : const <Map<String, dynamic>>[];
    if (albums.isEmpty) return null;
    final album = albums.first;
    final name = (album['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;
    return LastFmTopAlbum(
      name: name,
      artist: artist,
      url: _safeAlbumUrl(album['url'], artist: artist, album: name),
      musicBrainzId: _nonEmpty(album['mbid']),
      imageUrl: _imageUrl(album['image']),
    );
  }

  Future<Uri?> artistImage(String artist) async =>
      (await topAlbum(artist))?.imageUrl;

  Future<Uri?> trackImage({
    required String artist,
    required String track,
  }) async {
    final json = await _request(<String, String>{
      'method': 'track.getinfo',
      'artist': artist,
      'track': track,
    });
    final root = json['track'];
    if (root is! Map<String, dynamic>) return null;
    final album = root['album'];
    final albumImage =
        album is Map<String, dynamic> ? _imageUrl(album['image']) : null;
    return albumImage ?? _imageUrl(root['image']);
  }

  Future<Map<String, dynamic>> _request(Map<String, String> query) async {
    final uri = endpoint.replace(queryParameters: <String, String>{
      ...endpoint.queryParameters,
      ...query,
      'api_key': apiKey.trim(),
      'format': 'json',
      'autocorrect': '1',
    });
    http.Response response;
    try {
      response = await _httpClient.get(uri).timeout(timeout);
    } catch (error) {
      throw LastFmRecommendationException(
        'Could not reach Last.fm. Check your connection and try again.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const LastFmRecommendationException(
        'Last.fm returned an unreadable response.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LastFmRecommendationException(
        'Last.fm returned an unexpected response.',
      );
    }
    final apiCode = (decoded['error'] as num?)?.toInt();
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        apiCode != null) {
      throw LastFmRecommendationException(
        decoded['message'] as String? ??
            'Last.fm could not load recommendations.',
        apiCode: apiCode,
      );
    }
    return decoded;
  }

  LastFmRecommendationCandidate? _parseArtist(Map<String, dynamic> json) {
    final name = (json['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;
    return LastFmRecommendationCandidate(
      kind: MusicRecommendationKind.artist,
      name: name,
      match: _match(json['match']),
      url: _safeUrl(json['url'], artist: name),
      musicBrainzId: _nonEmpty(json['mbid']),
      imageUrl: _imageUrl(json['image']),
    );
  }

  LastFmRecommendationCandidate? _parseTrack(Map<String, dynamic> json) {
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
      match: _match(json['match']),
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

  static String? _nonEmpty(Object? raw) {
    final value = raw is String ? raw.trim() : '';
    return value.isEmpty ? null : value;
  }

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
    if (_ownsHttpClient) _httpClient.close();
  }
}
