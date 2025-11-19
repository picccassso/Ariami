import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_models.dart';

/// Search service with ranking algorithm and recent searches
class SearchService {
  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecentSearches = 10;

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
  // RECENT SEARCHES
  // ============================================================================

  /// Get recent searches (last 10)
  Future<List<String>> getRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentSearchesKey) ?? [];
  }

  /// Add search to recent searches (max 10)
  Future<void> addRecentSearch(String query) async {
    if (query.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentSearchesKey) ?? [];

    // Remove if already exists (to move it to front)
    recent.remove(query);

    // Add to front
    recent.insert(0, query);

    // Keep only last 10
    if (recent.length > _maxRecentSearches) {
      recent.removeRange(_maxRecentSearches, recent.length);
    }

    await prefs.setStringList(_recentSearchesKey, recent);
  }

  /// Clear all recent searches
  Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchesKey);
  }

  /// Remove a specific recent search
  Future<void> removeRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentSearchesKey) ?? [];
    recent.remove(query);
    await prefs.setStringList(_recentSearchesKey, recent);
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
