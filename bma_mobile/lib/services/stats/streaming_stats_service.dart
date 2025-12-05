import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/song.dart';
import '../../models/song_stats.dart';
import '../../database/stats_database.dart';

/// Service for tracking streaming statistics across the app with SQLite persistence
class StreamingStatsService extends ChangeNotifier {
  // Singleton pattern
  static final StreamingStatsService _instance =
      StreamingStatsService._internal();

  factory StreamingStatsService() => _instance;

  StreamingStatsService._internal();

  // Dependencies
  late StatsDatabase _database;

  // In-memory cache for instant UI updates
  final Map<String, SongStats> _statsCache = {};

  // Playback tracking
  Timer? _playbackTimer;
  Song? _currentSong;
  DateTime? _startTime;

  // Streams for UI updates (initialized at startup)
  late StreamController<List<SongStats>> _topSongsStreamController;

  Stream<List<SongStats>> get topSongsStream => _topSongsStreamController.stream;

  /// Initialize the service
  Future<void> initialize() async {
    // Initialize stream controller with onListen callback
    // This ensures new subscribers immediately receive current data
    _topSongsStreamController = StreamController<List<SongStats>>.broadcast(
      onListen: () {
        // Re-emit current state when new subscribers join
        _emitTopSongs();
      },
    );

    _database = await StatsDatabase.create();

    // Load all stats from SQLite into memory cache
    _statsCache.clear();
    final allStats = await _database.getAllStats();
    for (final stat in allStats) {
      _statsCache[stat.songId] = stat;
    }

    _emitTopSongs();
    print('[StreamingStatsService] Initialized with ${_statsCache.length} cached songs');
  }

  /// Called when a song starts playing
  void onSongStarted(Song song) {
    print('[StreamingStatsService] Song started: ${song.title}');
    print('[StreamingStatsService] Is first song? ${_currentSong == null}');

    // If a song is already playing, stop tracking it first
    if (_currentSong != null) {
      print('[StreamingStatsService] Previous song was still playing, finalizing ${_currentSong!.title}');
      // Synchronously finalize the previous song (without awaiting to keep onSongStarted synchronous)
      _finalizePreviousSong();
    }

    _currentSong = song;
    _startTime = DateTime.now();

    // Cancel any previous timer
    _playbackTimer?.cancel();

    // Start 30-second timer - use async callback to allow awaiting
    _playbackTimer = Timer(const Duration(seconds: 30), () async {
      print('[StreamingStatsService] 30-second timer fired for: ${_currentSong?.title ?? "NULL"}');
      await _recordPlay();
    });
    print('[StreamingStatsService] Timer set for 30 seconds');
  }

  /// Internal: Finalize the current song's stats without awaiting (for onSongStarted)
  void _finalizePreviousSong() {
    if (_currentSong == null || _startTime == null) return;

    final elapsedTime = DateTime.now().difference(_startTime!);
    if (elapsedTime.inSeconds > 0) {
      // Update time in background (fire and forget)
      _updateStreamingTime(elapsedTime).catchError((e) {
        print('[StreamingStatsService] Error updating time for previous song: $e');
      });
    }
  }

  /// Called when a song is stopped, paused, or skipped
  Future<void> onSongStopped() async {
    if (_currentSong == null) {
      print('[StreamingStatsService] onSongStopped called but no current song');
      return;
    }

    print('[StreamingStatsService] Song stopped: ${_currentSong!.title}');

    // Cancel timer
    _playbackTimer?.cancel();

    // Record time if song was played for any duration
    if (_startTime != null) {
      final elapsedTime = DateTime.now().difference(_startTime!);
      print('[StreamingStatsService] Elapsed time for ${_currentSong!.title}: ${elapsedTime.inSeconds}s');
      if (elapsedTime.inSeconds > 0) {
        await _updateStreamingTime(elapsedTime);
      }
    }

    _currentSong = null;
    _startTime = null;
  }

  /// Internal: Record a play when 30 seconds have been reached
  Future<void> _recordPlay() async {
    print('[StreamingStatsService] _recordPlay called - _currentSong: ${_currentSong?.title ?? "NULL"}');

    if (_currentSong == null) {
      print('[StreamingStatsService] ERROR: _recordPlay called but no current song');
      return;
    }

    print('[StreamingStatsService] Recording play for: ${_currentSong!.title}');

    final songId = _currentSong!.id;
    final existingStats = _statsCache[songId] ??
        SongStats(
          songId: songId,
          playCount: 0,
          totalTime: Duration.zero,
          firstPlayed: DateTime.now(),
        );

    // Increment play count
    final updatedStats = existingStats.copyWith(
      playCount: existingStats.playCount + 1,
      lastPlayed: DateTime.now(),
      songTitle: _currentSong?.title,
      songArtist: _currentSong?.artist,
      albumId: _currentSong?.albumId,
      album: _currentSong?.album,
      albumArtist: _currentSong?.albumArtist,
    );

    // Update in-memory cache IMMEDIATELY
    _statsCache[songId] = updatedStats;

    print('[StreamingStatsService] Play count incremented: ${updatedStats.playCount}');
    print('[StreamingStatsService] Cache now has ${_statsCache.length} songs');

    // Write to database IMMEDIATELY (no debouncing)
    await _database.saveSongStats(updatedStats);
    print('[StreamingStatsService] Stats saved to database');

    // Emit to UI instantly
    _emitTopSongs();
    print('[StreamingStatsService] Emitted top songs to stream');
  }

  /// Internal: Update total streaming time
  Future<void> _updateStreamingTime(Duration elapsed) async {
    if (_currentSong == null) {
      print('[StreamingStatsService] _updateStreamingTime called but no current song');
      return;
    }

    final songId = _currentSong!.id;
    final existingStats = _statsCache[songId] ??
        SongStats(
          songId: songId,
          playCount: 0,
          totalTime: Duration.zero,
          firstPlayed: DateTime.now(),
        );

    // Add elapsed time to total
    final newTotalTime =
        Duration(seconds: existingStats.totalTime.inSeconds + elapsed.inSeconds);

    print('[StreamingStatsService] Updating time for ${_currentSong!.title}: adding ${elapsed.inSeconds}s (total now: ${newTotalTime.inSeconds}s)');

    final updatedStats = existingStats.copyWith(
      totalTime: newTotalTime,
      lastPlayed: DateTime.now(),
      songTitle: _currentSong?.title,
      songArtist: _currentSong?.artist,
      albumId: _currentSong?.albumId,
      album: _currentSong?.album,
      albumArtist: _currentSong?.albumArtist,
    );

    // Update in-memory cache IMMEDIATELY
    _statsCache[songId] = updatedStats;

    // Write to database IMMEDIATELY (no debouncing)
    await _database.saveSongStats(updatedStats);

    // Emit to UI instantly
    _emitTopSongs();
  }

  /// Get all stats (from in-memory cache for instant access)
  List<SongStats> getAllStats() {
    return _statsCache.values
        .where((stat) => stat.playCount > 0)
        .toList();
  }

  /// Get top songs (default 20) from in-memory cache
  List<SongStats> getTopSongs({int limit = 20}) {
    final allStats = getAllStats();
    // Sort by play count descending
    allStats.sort((a, b) => b.playCount.compareTo(a.playCount));
    return allStats.take(limit).toList();
  }

  /// Get total statistics from in-memory cache
  ({int totalSongsPlayed, Duration totalTimeStreamed}) getTotalStats() {
    final allStats = getAllStats();
    int totalSongs = allStats.length;
    Duration totalTime = Duration.zero;

    for (final stat in allStats) {
      totalTime += stat.totalTime;
    }

    return (totalSongsPlayed: totalSongs, totalTimeStreamed: totalTime);
  }

  /// Get average daily listening time (computed from in-memory cache)
  Duration getAverageDailyTime() {
    final stats = getTotalStats();  // Uses in-memory cache, instant
    if (stats.totalSongsPlayed == 0) return Duration.zero;

    // Estimate daily average based on total time and assumed listening days
    // Simple approach: assume 30 days of activity
    return Duration(seconds: stats.totalTimeStreamed.inSeconds ~/ 30);
  }

  /// Reset all statistics
  Future<void> resetAllStats() async {
    print('[StreamingStatsService] Resetting all stats');
    _statsCache.clear();
    await _database.resetAllStats();
    _emitTopSongs();
    notifyListeners();
  }

  /// Get stats for a specific song from in-memory cache
  SongStats? getSongStats(String songId) {
    return _statsCache[songId];
  }

  /// Emit updated top songs to stream
  void _emitTopSongs() {
    final topSongs = getTopSongs();
    print('[StreamingStatsService] _emitTopSongs: emitting ${topSongs.length} songs to stream');
    if (topSongs.isNotEmpty) {
      print('[StreamingStatsService] Top song: ${topSongs.first.songTitle} (${topSongs.first.playCount} plays)');
    }
    _topSongsStreamController.add(topSongs);
    notifyListeners();
  }

  /// Public refresh method for UI to request updated stats
  void refreshTopSongs() {
    _emitTopSongs();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _topSongsStreamController.close();
    super.dispose();
  }
}
