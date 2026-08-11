import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../app_version.dart';
import '../search/search_normalizer.dart';

class MusicBrainzIdentity {
  const MusicBrainzIdentity({
    required this.id,
    required this.name,
    this.artist,
  });

  final String id;
  final String name;
  final String? artist;
}

/// Best-effort identity helper. MusicBrainz is deliberately not involved in
/// ranking; it only assigns stable ids and canonical names to Last.fm results.
class MusicBrainzIdentityClient {
  MusicBrainzIdentityClient({
    http.Client? httpClient,
    Uri? endpoint,
    this.requestSpacing = const Duration(milliseconds: 1100),
    this.timeout = const Duration(seconds: 12),
    this.userAgent = 'Ariami/$kAriamiVersion (https://ariami.xyz)',
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        endpoint = endpoint ?? Uri.https('musicbrainz.org', '/ws/2/');

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Uri endpoint;
  final Duration requestSpacing;
  final Duration timeout;
  final String userAgent;
  DateTime? _lastRequestAt;

  Future<MusicBrainzIdentity?> searchArtist(String artist) async {
    final rows = await _search(
      entity: 'artist',
      query: 'artist:"${_escapeQuery(artist)}"',
    );
    final expected = SearchNormalizer.normalizeString(artist);
    for (final row in rows) {
      final name = row['name'] as String? ?? '';
      final score = (row['score'] as num?)?.toInt() ?? 0;
      final id = row['id'] as String? ?? '';
      if (id.isNotEmpty &&
          score >= 90 &&
          SearchNormalizer.normalizeString(name) == expected) {
        return MusicBrainzIdentity(id: id, name: name);
      }
    }
    return null;
  }

  Future<MusicBrainzIdentity?> searchRecording({
    required String title,
    required String artist,
  }) async {
    final rows = await _search(
      entity: 'recording',
      query: 'recording:"${_escapeQuery(title)}" AND '
          'artist:"${_escapeQuery(artist)}"',
    );
    final expectedTitle = SearchNormalizer.normalizeString(title);
    final expectedArtist = SearchNormalizer.normalizeString(artist);
    for (final row in rows) {
      final name = row['title'] as String? ?? '';
      final score = (row['score'] as num?)?.toInt() ?? 0;
      final id = row['id'] as String? ?? '';
      final credit = _artistCredit(row['artist-credit']);
      final normalizedCredit = SearchNormalizer.normalizeString(credit);
      if (id.isNotEmpty &&
          score >= 90 &&
          SearchNormalizer.normalizeString(name) == expectedTitle &&
          (normalizedCredit == expectedArtist ||
              normalizedCredit.contains(expectedArtist) ||
              expectedArtist.contains(normalizedCredit))) {
        return MusicBrainzIdentity(id: id, name: name, artist: credit);
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _search({
    required String entity,
    required String query,
  }) async {
    await _respectRateLimit();
    final basePath =
        endpoint.path.endsWith('/') ? endpoint.path : '${endpoint.path}/';
    final uri = endpoint.replace(
      path: '$basePath$entity/',
      queryParameters: <String, String>{
        'query': query,
        'limit': '3',
        'fmt': 'json',
      },
    );
    try {
      final response = await _httpClient.get(
        uri,
        headers: <String, String>{
          'Accept': 'application/json',
          'User-Agent': userAgent,
        },
      ).timeout(timeout);
      _lastRequestAt = DateTime.now();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const <Map<String, dynamic>>[];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final key = entity == 'artist' ? 'artists' : 'recordings';
      final rows = decoded[key];
      return rows is List<dynamic>
          ? rows.whereType<Map<String, dynamic>>().toList(growable: false)
          : const <Map<String, dynamic>>[];
    } catch (_) {
      _lastRequestAt = DateTime.now();
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _respectRateLimit() async {
    final last = _lastRequestAt;
    if (last == null || requestSpacing == Duration.zero) return;
    final remaining = requestSpacing - DateTime.now().difference(last);
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
  }

  static String _artistCredit(Object? raw) {
    if (raw is! List<dynamic>) return '';
    final parts = <String>[];
    for (final item in raw.whereType<Map<String, dynamic>>()) {
      final name = item['name'] as String? ??
          ((item['artist'] as Map<String, dynamic>?)?['name'] as String? ?? '');
      if (name.isNotEmpty) parts.add(name);
      final join = item['joinphrase'] as String? ?? '';
      if (join.isNotEmpty) parts.add(join);
    }
    return parts.join().trim();
  }

  static String _escapeQuery(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
