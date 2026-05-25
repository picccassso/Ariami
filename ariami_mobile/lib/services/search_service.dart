import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_models.dart';

/// Search service with ranking algorithm and recent songs
class SearchService {
  static const String _recentSongsKey = 'recent_songs';
  static const int _maxRecentSongs = 30;

  /// Search songs and albums with ranking algorithm
  /// Returns SearchResults with songs first, then albums
  SearchResults search(
      String query, List<SongModel> songs, List<AlbumModel> albums) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return SearchResults(songs: [], albums: []);
    }

    final tokens = _tokenize(normalizedQuery);
    final uniqueSongs = deduplicateSongs(songs);
    final uniqueAlbums = deduplicateAlbums(albums);
    final albumById = {for (final album in uniqueAlbums) album.id: album};

    // Search and rank songs
    final rankedSongs = _searchAndRankSongs(tokens, uniqueSongs, albumById);
    final displayUniqueRankedSongs = _deduplicateDisplaySongs(rankedSongs);

    // Search and rank albums
    final rankedAlbums = _searchAndRankAlbums(tokens, uniqueAlbums);

    return SearchResults(
      songs: displayUniqueRankedSongs,
      albums: rankedAlbums,
    );
  }

  /// Remove duplicate songs while preserving stable ordering.
  ///
  /// Deduping is done in two stages:
  /// 1) by song ID
  /// 2) by canonical metadata fingerprint (title/artist/album/duration/track)
  List<SongModel> deduplicateSongs(List<SongModel> songs) {
    if (songs.length < 2) return songs;

    final byId = <String, SongModel>{};
    final orderedIds = <String>[];
    for (final song in songs) {
      final existing = byId[song.id];
      if (existing == null) {
        byId[song.id] = song;
        orderedIds.add(song.id);
      } else {
        byId[song.id] = _pickPreferredSong(existing, song);
      }
    }

    final byFingerprint = <String, SongModel>{};
    final orderedFingerprints = <String>[];
    for (final id in orderedIds) {
      final song = byId[id]!;
      final fingerprint = _songFingerprint(song);
      final existing = byFingerprint[fingerprint];
      if (existing == null) {
        byFingerprint[fingerprint] = song;
        orderedFingerprints.add(fingerprint);
      } else {
        byFingerprint[fingerprint] = _pickPreferredSong(existing, song);
      }
    }

    return orderedFingerprints.map((key) => byFingerprint[key]!).toList();
  }

  /// Remove duplicate albums while preserving stable ordering.
  ///
  /// Deduping is done in two stages:
  /// 1) by album ID
  /// 2) by canonical metadata fingerprint (title/artist)
  List<AlbumModel> deduplicateAlbums(List<AlbumModel> albums) {
    if (albums.length < 2) return albums;

    final byId = <String, AlbumModel>{};
    final orderedIds = <String>[];
    for (final album in albums) {
      final existing = byId[album.id];
      if (existing == null) {
        byId[album.id] = album;
        orderedIds.add(album.id);
      } else {
        byId[album.id] = _pickPreferredAlbum(existing, album);
      }
    }

    final byFingerprint = <String, AlbumModel>{};
    final orderedFingerprints = <String>[];
    for (final id in orderedIds) {
      final album = byId[id]!;
      final fingerprint = _albumFingerprint(album);
      final existing = byFingerprint[fingerprint];
      if (existing == null) {
        byFingerprint[fingerprint] = album;
        orderedFingerprints.add(fingerprint);
      } else {
        byFingerprint[fingerprint] = _pickPreferredAlbum(existing, album);
      }
    }

    return orderedFingerprints.map((key) => byFingerprint[key]!).toList();
  }

  static const int _exactTier = 3;
  static const int _prefixTier = 2;
  static const int _substringTier = 1;

  List<String> _tokenize(String query) {
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  int _tokenMatchTier(String token, String field) {
    if (field.isEmpty) return 0;
    if (field == token) return _exactTier;
    if (field.startsWith(token)) return _prefixTier;
    if (field.contains(token)) return _substringTier;
    return 0;
  }

  int _bestTokenTierAcrossFields(String token, List<String> fields) {
    var best = 0;
    for (final field in fields) {
      final tier = _tokenMatchTier(token, field);
      if (tier > best) {
        best = tier;
      }
    }
    return best;
  }

  /// Returns bucket index: 0 exact, 1 prefix, 2 substring; null if no match.
  int? _matchBucketForFields(List<String> tokens, List<String> fields) {
    if (tokens.isEmpty) return null;

    if (tokens.length == 1) {
      final tier = _bestTokenTierAcrossFields(tokens.single, fields);
      if (tier == _exactTier) return 0;
      if (tier == _prefixTier) return 1;
      if (tier == _substringTier) return 2;
      return null;
    }

    final tiers = tokens
        .map((token) => _bestTokenTierAcrossFields(token, fields))
        .toList();
    if (tiers.any((tier) => tier == 0)) return null;

    final minTier = tiers.reduce((a, b) => a < b ? a : b);
    if (minTier == _exactTier) return 0;
    if (minTier >= _prefixTier) return 1;
    return 2;
  }

  List<String> _songSearchFields(
    SongModel song,
    Map<String, AlbumModel> albumById,
  ) {
    final album = albumById[song.albumId ?? ''];
    return [
      song.title.toLowerCase(),
      song.artist.toLowerCase(),
      album?.title.toLowerCase() ?? '',
      album?.artist.toLowerCase() ?? '',
    ];
  }

  /// Search and rank songs by relevance
  List<SongModel> _searchAndRankSongs(
    List<String> tokens,
    List<SongModel> songs,
    Map<String, AlbumModel> albumById,
  ) {
    final exactMatches = <SongModel>[];
    final prefixMatches = <SongModel>[];
    final substringMatches = <SongModel>[];

    for (final song in songs) {
      final fields = _songSearchFields(song, albumById);
      final bucket = _matchBucketForFields(tokens, fields);
      switch (bucket) {
        case 0:
          exactMatches.add(song);
        case 1:
          prefixMatches.add(song);
        case 2:
          substringMatches.add(song);
        default:
          break;
      }
    }

    // Combine in ranking order: exact → prefix → substring
    return [...exactMatches, ...prefixMatches, ...substringMatches];
  }

  /// Final display-level dedupe for ranked song results.
  ///
  /// This intentionally ignores album/track IDs so the same audible track
  /// doesn't appear multiple times if ingested through multiple sources.
  List<SongModel> _deduplicateDisplaySongs(List<SongModel> songs) {
    if (songs.length < 2) return songs;

    final unique = <String, SongModel>{};
    final orderedKeys = <String>[];
    for (final song in songs) {
      final key = _displaySongFingerprint(song);
      if (!unique.containsKey(key)) {
        unique[key] = song;
        orderedKeys.add(key);
      } else {
        unique[key] = _pickPreferredSong(unique[key]!, song);
      }
    }

    return orderedKeys.map((key) => unique[key]!).toList();
  }

  /// Search and rank albums by relevance
  List<AlbumModel> _searchAndRankAlbums(
    List<String> tokens,
    List<AlbumModel> albums,
  ) {
    final exactMatches = <AlbumModel>[];
    final prefixMatches = <AlbumModel>[];
    final substringMatches = <AlbumModel>[];

    for (final album in albums) {
      final fields = [
        album.title.toLowerCase(),
        album.artist.toLowerCase(),
      ];
      final bucket = _matchBucketForFields(tokens, fields);
      switch (bucket) {
        case 0:
          exactMatches.add(album);
        case 1:
          prefixMatches.add(album);
        case 2:
          substringMatches.add(album);
        default:
          break;
      }
    }

    // Combine in ranking order: exact → prefix → substring
    return [...exactMatches, ...prefixMatches, ...substringMatches];
  }

  String _songFingerprint(SongModel song) {
    return [
      _normalize(song.title),
      _normalize(song.artist),
      _normalize(song.albumId ?? ''),
      song.duration.toString(),
      song.trackNumber?.toString() ?? '',
    ].join('|');
  }

  String _displaySongFingerprint(SongModel song) {
    final durationBucket = (song.duration / 2).round();
    return [
      _normalize(song.title),
      _normalize(song.artist),
      durationBucket.toString(),
    ].join('|');
  }

  String _albumFingerprint(AlbumModel album) {
    return [
      _normalize(album.title),
      _normalize(album.artist),
    ].join('|');
  }

  String _normalize(String value) => value.trim().toLowerCase();

  SongModel _pickPreferredSong(SongModel a, SongModel b) {
    final scoreA = _songMetadataScore(a);
    final scoreB = _songMetadataScore(b);
    return scoreB > scoreA ? b : a;
  }

  int _songMetadataScore(SongModel song) {
    var score = 0;
    if (song.albumId != null && song.albumId!.trim().isNotEmpty) score += 2;
    if (song.duration > 0) score += 1;
    if (song.trackNumber != null) score += 1;
    return score;
  }

  AlbumModel _pickPreferredAlbum(AlbumModel a, AlbumModel b) {
    final scoreA = _albumMetadataScore(a);
    final scoreB = _albumMetadataScore(b);
    return scoreB > scoreA ? b : a;
  }

  int _albumMetadataScore(AlbumModel album) {
    var score = 0;
    if (album.coverArt != null && album.coverArt!.trim().isNotEmpty) score += 2;
    if (album.songCount > 0) score += 1;
    if (album.duration > 0) score += 1;
    return score;
  }

  // ============================================================================
  // RECENT SONGS
  // ============================================================================

  /// Get recent songs (last 30)
  Future<List<SongModel>> getRecentSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_recentSongsKey) ?? [];

    return jsonList.map((jsonStr) {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SongModel.fromJson(json);
    }).toList();
  }

  /// Add song to recent songs (max 30)
  Future<void> addRecentSong(SongModel song) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_recentSongsKey) ?? [];

    // Convert to SongModel list
    final recentSongs = jsonList.map((jsonStr) {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SongModel.fromJson(json);
    }).toList();

    // Remove if already exists (to move it to front)
    recentSongs.removeWhere((s) => s.id == song.id);

    // Add to front
    recentSongs.insert(0, song);

    // Keep only last 30
    if (recentSongs.length > _maxRecentSongs) {
      recentSongs.removeRange(_maxRecentSongs, recentSongs.length);
    }

    // Convert back to JSON strings
    final updatedJsonList =
        recentSongs.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_recentSongsKey, updatedJsonList);
  }

  /// Clear all recent songs
  Future<void> clearRecentSongs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSongsKey);
  }

  /// Remove a specific recent song
  Future<void> removeRecentSong(String songId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_recentSongsKey) ?? [];

    final recentSongs = jsonList.map((jsonStr) {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SongModel.fromJson(json);
    }).toList();

    recentSongs.removeWhere((s) => s.id == songId);

    final updatedJsonList =
        recentSongs.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_recentSongsKey, updatedJsonList);
  }

  /// Insert a song at a specific index in recent songs
  Future<void> insertRecentSongAt(SongModel song, int index) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_recentSongsKey) ?? [];

    final recentSongs = jsonList.map((jsonStr) {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SongModel.fromJson(json);
    }).toList();

    // Remove if already exists
    recentSongs.removeWhere((s) => s.id == song.id);

    // Insert at the specified index (clamped to valid range)
    final insertIndex = index.clamp(0, recentSongs.length).toInt();
    recentSongs.insert(insertIndex, song);

    // Keep only last 30
    if (recentSongs.length > _maxRecentSongs) {
      recentSongs.removeRange(_maxRecentSongs, recentSongs.length);
    }

    // Convert back to JSON strings
    final updatedJsonList =
        recentSongs.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_recentSongsKey, updatedJsonList);
  }
}

/// Search results container
class SearchResults {
  final List<SongModel> songs;
  final List<AlbumModel> albums;

  SearchResults({
    required this.songs,
    required this.albums,
  });

  bool get isEmpty => songs.isEmpty && albums.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

/// Debounced search helper
class DebouncedSearch {
  final Duration delay;
  Timer? _timer;

  DebouncedSearch({this.delay = const Duration(milliseconds: 300)});

  /// Execute callback after delay, cancelling previous pending callbacks
  void run(void Function() callback) {
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }

  /// Cancel pending callback
  void cancel() {
    _timer?.cancel();
  }
}
