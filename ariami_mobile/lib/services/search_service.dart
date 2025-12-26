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
  SearchResults search(String query, List<SongModel> songs, List<AlbumModel> albums) {
    if (query.isEmpty) {
      return SearchResults(songs: [], albums: []);
    }

    final lowerQuery = query.toLowerCase();

    // Search and rank songs
    final rankedSongs = _searchAndRankSongs(lowerQuery, songs);

    // Search and rank albums
    final rankedAlbums = _searchAndRankAlbums(lowerQuery, albums);

    return SearchResults(
      songs: rankedSongs,
      albums: rankedAlbums,
    );
  }

  /// Search and rank songs by relevance
  List<SongModel> _searchAndRankSongs(String query, List<SongModel> songs) {
    final exactMatches = <SongModel>[];
    final prefixMatches = <SongModel>[];
    final substringMatches = <SongModel>[];

    for (final song in songs) {
      final titleLower = song.title.toLowerCase();
      final artistLower = song.artist.toLowerCase();

      // Check for exact matches (title or artist)
      if (titleLower == query || artistLower == query) {
        exactMatches.add(song);
        continue;
      }

      // Check for prefix matches (starts with query)
      if (titleLower.startsWith(query) || artistLower.startsWith(query)) {
        prefixMatches.add(song);
        continue;
      }

      // Check for substring matches (contains query)
      if (titleLower.contains(query) || artistLower.contains(query)) {
        substringMatches.add(song);
      }
    }

    // Combine in ranking order: exact → prefix → substring
    return [...exactMatches, ...prefixMatches, ...substringMatches];
  }

  /// Search and rank albums by relevance
  List<AlbumModel> _searchAndRankAlbums(String query, List<AlbumModel> albums) {
    final exactMatches = <AlbumModel>[];
    final prefixMatches = <AlbumModel>[];
    final substringMatches = <AlbumModel>[];

    for (final album in albums) {
      final titleLower = album.title.toLowerCase();
      final artistLower = album.artist.toLowerCase();

      // Check for exact matches (title or artist)
      if (titleLower == query || artistLower == query) {
        exactMatches.add(album);
        continue;
      }

      // Check for prefix matches (starts with query)
      if (titleLower.startsWith(query) || artistLower.startsWith(query)) {
        prefixMatches.add(album);
        continue;
      }

      // Check for substring matches (contains query)
      if (titleLower.contains(query) || artistLower.contains(query)) {
        substringMatches.add(album);
      }
    }

    // Combine in ranking order: exact → prefix → substring
    return [...exactMatches, ...prefixMatches, ...substringMatches];
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
    final updatedJsonList = recentSongs.map((s) => jsonEncode(s.toJson())).toList();
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

    final updatedJsonList = recentSongs.map((s) => jsonEncode(s.toJson())).toList();
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
