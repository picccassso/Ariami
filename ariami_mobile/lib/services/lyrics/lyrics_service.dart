import 'package:ariami_core/models/lyrics_models.dart';
import '../api/connection_service.dart';
import '../download/download_manager.dart';

/// Centralized service for fetching, caching, and accessing lyrics on mobile.
class LyricsService {
  static final LyricsService _instance = LyricsService._internal();
  factory LyricsService() => _instance;
  LyricsService._internal();

  final Map<String, SongLyrics> _cache = {};

  /// Fetches lyrics for the given [songId].
  ///
  /// Checks the session cache, then offline durable storage, and finally the
  /// server. Misses are not cached so a transient network failure doesn't
  /// hide lyrics for the rest of the session.
  Future<SongLyrics?> getLyrics(String songId) async {
    final cached = _cache[songId];
    if (cached != null) return cached;

    final lyrics = await DownloadManager().getDownloadedLyrics(songId) ??
        await ConnectionService().apiClient?.getLyrics(songId);
    if (lyrics != null) _cache[songId] = lyrics;
    return lyrics;
  }

  /// Clears in-memory cache.
  void clearCache() {
    _cache.clear();
  }
}
