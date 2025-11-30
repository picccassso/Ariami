import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/song.dart';
import '../../models/song_stats.dart';
import '../../database/stats_database.dart';

/// Service for tracking streaming statistics across the app
class StreamingStatsService extends ChangeNotifier {
  // Singleton pattern
  static final StreamingStatsService _instance =
      StreamingStatsService._internal();

  factory StreamingStatsService() => _instance;

  StreamingStatsService._internal();

  // Dependencies
  late StatsDatabase _database;

  // Playback tracking
  Timer? _playbackTimer;
  Song? _currentSong;
  DateTime? _startTime;

  // Streams for UI updates (initialized at startup)
  late StreamController<List<SongStats>> _topSongsStreamController;

  Stream<List<SongStats>> get topSongsStream => _topSongsStreamController.stream;

  /// Initialize the service
  Future<void> initialize() async {
    // Initialize stream controller first (before any emissions)
    _topSongsStreamController = StreamController<List<SongStats>>.broadcast();

    _database = await StatsDatabase.create();
    _emitTopSongs();
    print('[StreamingStatsService] Initialized');
  }

  /// Called when a song starts playing
  void onSongStarted(Song song) {
    print('[StreamingStatsService] Song started: ${song.title}');

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
      await _recordPlay();
    });
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
    if (_currentSong == null) {
      print('[StreamingStatsService] _recordPlay called but no current song');
      return;
    }

    print('[StreamingStatsService] Recording play for: ${_currentSong!.title}');

    final songId = _currentSong!.id;
    final existingStats = _database.getSongStats(songId) ??
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
    );

    print('[StreamingStatsService] Saving play count: ${updatedStats.playCount}');
    await _database.saveSongStats(updatedStats);
    print('[StreamingStatsService] Play count saved successfully');
    _emitTopSongs();
  }

  /// Internal: Update total streaming time
  Future<void> _updateStreamingTime(Duration elapsed) async {
    if (_currentSong == null) {
      print('[StreamingStatsService] _updateStreamingTime called but no current song');
      return;
    }

    final songId = _currentSong!.id;
    final existingStats = _database.getSongStats(songId) ??
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
    );

    print('[StreamingStatsService] Saving streaming time...');
    await _database.saveSongStats(updatedStats);
    print('[StreamingStatsService] Streaming time saved successfully');
    _emitTopSongs();
  }

  /// Get all stats
  List<SongStats> getAllStats() {
    return _database.getAllStats();
  }

  /// Get top songs (default 20)
  List<SongStats> getTopSongs({int limit = 20}) {
    return _database.getTopSongs(limit: limit);
  }

  /// Get total statistics
  ({int totalSongsPlayed, Duration totalTimeStreamed}) getTotalStats() {
    return _database.getTotalStats();
  }

  /// Get average daily listening time
  Duration getAverageDailyTime() {
    return _database.getAverageDailyTime();
  }

  /// Reset all statistics
  Future<void> resetAllStats() async {
    print('[StreamingStatsService] Resetting all stats');
    await _database.resetAllStats();
    _emitTopSongs();
    notifyListeners();
  }

  /// Get stats for a specific song
  SongStats? getSongStats(String songId) {
    return _database.getSongStats(songId);
  }

  /// Emit updated top songs to stream
  void _emitTopSongs() {
    final topSongs = getTopSongs();
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
