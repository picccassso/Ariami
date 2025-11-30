import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_stats.dart';

/// Database layer for managing streaming statistics persistence
class StatsDatabase {
  static const String _statsKeyPrefix = 'stats_song_';
  static const String _allSongsKey = 'stats_all_song_ids';

  final SharedPreferences _prefs;

  StatsDatabase(this._prefs);

  /// Create instance from platform
  static Future<StatsDatabase> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StatsDatabase(prefs);
  }

  // ============================================================================
  // SONG STATS MANAGEMENT
  // ============================================================================

  /// Save stats for a single song
  Future<void> saveSongStats(SongStats stats) async {
    final key = '$_statsKeyPrefix${stats.songId}';
    final json = jsonEncode(stats.toJson());
    await _prefs.setString(key, json);

    // Add to list of all song IDs if not already there
    final allIds = _prefs.getStringList(_allSongsKey) ?? [];
    if (!allIds.contains(stats.songId)) {
      allIds.add(stats.songId);
      await _prefs.setStringList(_allSongsKey, allIds);
    }
  }

  /// Get stats for a single song (returns null if not found)
  SongStats? getSongStats(String songId) {
    final key = '$_statsKeyPrefix$songId';
    final json = _prefs.getString(key);
    if (json == null) return null;
    return SongStats.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// Get all songs with stats
  List<SongStats> getAllStats() {
    final allIds = _prefs.getStringList(_allSongsKey) ?? [];
    final stats = <SongStats>[];

    for (final songId in allIds) {
      final stat = getSongStats(songId);
      if (stat != null && stat.playCount > 0) {
        stats.add(stat);
      }
    }

    return stats;
  }

  /// Get top songs by play count (limited to top N)
  List<SongStats> getTopSongs({int limit = 20}) {
    final allStats = getAllStats();
    // Sort by play count descending
    allStats.sort((a, b) => b.playCount.compareTo(a.playCount));
    return allStats.take(limit).toList();
  }

  /// Get total stats across all songs
  ({int totalSongsPlayed, Duration totalTimeStreamed}) getTotalStats() {
    final allStats = getAllStats();
    int totalSongs = allStats.length;
    Duration totalTime = Duration.zero;

    for (final stat in allStats) {
      totalTime += stat.totalTime;
    }

    return (totalSongsPlayed: totalSongs, totalTimeStreamed: totalTime);
  }

  /// Get average listening time per day
  Duration getAverageDailyTime() {
    final total = getTotalStats();
    if (total.totalSongsPlayed == 0) return Duration.zero;

    // Estimate daily average based on total time and assumed listening days
    // Simple approach: assume 30 days of activity
    return Duration(seconds: total.totalTimeStreamed.inSeconds ~/ 30);
  }

  /// Reset all statistics
  Future<void> resetAllStats() async {
    final allIds = _prefs.getStringList(_allSongsKey) ?? [];
    for (final songId in allIds) {
      final key = '$_statsKeyPrefix$songId';
      await _prefs.remove(key);
    }
    await _prefs.remove(_allSongsKey);
  }

  /// Delete stats for a single song
  Future<void> deleteSongStats(String songId) async {
    final key = '$_statsKeyPrefix$songId';
    await _prefs.remove(key);

    // Remove from list of all song IDs
    final allIds = _prefs.getStringList(_allSongsKey) ?? [];
    allIds.remove(songId);
    await _prefs.setStringList(_allSongsKey, allIds);
  }

  /// Check if a song has been played
  bool hasBeenPlayed(String songId) {
    final stats = getSongStats(songId);
    return stats != null && stats.playCount > 0;
  }
}
