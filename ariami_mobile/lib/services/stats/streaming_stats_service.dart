import 'dart:async';
import 'dart:ui' show AppExitResponse, ViewFocusEvent;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../models/song.dart';
import '../../models/song_stats.dart';
import '../../models/artist_stats.dart';
import '../../models/album_stats.dart';
import '../../database/stats_database.dart';

/// Service for tracking streaming statistics across the app with SQLite persistence.
///
/// Key behaviours:
/// - A "play" is counted once per play-action when cumulative listening time
///   reaches 30s.
/// - Cumulative time persists across pause/resume within the same play-action.
/// - Short songs (< 30s) that complete naturally always count as 1 play.
/// - Time is tracked via audio position updates to avoid inflating stats during
///   buffering, loading, or seeks.
/// - Database writes are debounced (5s) to reduce SQLite pressure.
/// - Stats are flushed immediately when the app is backgrounded or killed.
class StreamingStatsService extends ChangeNotifier implements WidgetsBindingObserver {
  // Singleton pattern
  static final StreamingStatsService _instance =
      StreamingStatsService._internal();

  factory StreamingStatsService() => _instance;

  StreamingStatsService._internal();

  // Dependencies
  late StatsDatabase _database;

  // In-memory cache for instant UI updates
  final Map<String, SongStats> _statsCache = {};

  // ============================================================================
  // SESSION STATE
  // ============================================================================

  /// The song currently being tracked (actively playing).
  Song? _currentSong;

  /// Listening time accumulated during the current uninterrupted segment.
  Duration _sessionListenedTime = Duration.zero;

  /// Total listening time for this play-action that has already been written
  /// to the in-memory cache. Used to compute the 30s threshold across pauses.
  Duration _sessionTimeAlreadyCached = Duration.zero;

  /// Whether a play has already been recorded for the current play-action.
  bool _sessionPlayRecorded = false;

  Duration? _lastPosition;

  // ============================================================================
  // DEBOUNCED PERSISTENCE
  // ============================================================================
  Timer? _dbFlushTimer;
  static const Duration _dbFlushInterval = Duration(seconds: 5);
  final Map<String, SongStats> _dirtyStats = {};
  bool _isFlushing = false;

  // ============================================================================
  // STREAMS FOR UI UPDATES
  // ============================================================================
  late StreamController<List<SongStats>> _topSongsStreamController;
  late StreamController<List<ArtistStats>> _topArtistsStreamController;
  late StreamController<List<AlbumStats>> _topAlbumsStreamController;

  Stream<List<SongStats>> get topSongsStream =>
      _topSongsStreamController.stream;
  Stream<List<ArtistStats>> get topArtistsStream =>
      _topArtistsStreamController.stream;
  Stream<List<AlbumStats>> get topAlbumsStream =>
      _topAlbumsStreamController.stream;

  /// Initialize the service
  Future<void> initialize() async {
    _topSongsStreamController = StreamController<List<SongStats>>.broadcast(
      onListen: () => _emitTopSongs(),
    );

    _topArtistsStreamController = StreamController<List<ArtistStats>>.broadcast(
      onListen: () => _emitTopArtists(),
    );

    _topAlbumsStreamController = StreamController<List<AlbumStats>>.broadcast(
      onListen: () => _emitTopAlbums(),
    );

    _database = await StatsDatabase.create();

    // Load all stats from SQLite into memory cache
    _statsCache.clear();
    final allStats = await _database.getAllStats();
    for (final stat in allStats) {
      _statsCache[stat.songId] = stat;
    }

    WidgetsBinding.instance.addObserver(this);

    _emitTopSongs();
    _emitTopArtists();
    _emitTopAlbums();
    print(
        '[StreamingStatsService] Initialized with ${_statsCache.length} cached songs');
  }

  // ============================================================================
  // PLAYBACK LIFECYCLE
  // ============================================================================

  /// Called when a song starts playing.
  ///
  /// [isResume] should be `true` when the same song is being resumed from
  /// pause. This preserves cumulative listening time and ensures the play
  /// count is not double-counted.
  void onSongStarted(Song song, {bool isResume = false}) {
    print(
        '[StreamingStatsService] Song started: ${song.title}, isResume=$isResume');

    // If a different song is currently playing (or the same song is being
    // restarted rather than resumed), finalize its session first.
    if (_currentSong != null &&
        (_currentSong!.id != song.id || !isResume)) {
      print(
          '[StreamingStatsService] Finalizing previous song: ${_currentSong!.title}');
      final previousSong = _currentSong!;
      final listenedTime = _sessionListenedTime;
      final playRecorded = _sessionPlayRecorded;
      unawaited(_finalizeSessionForSong(
        previousSong,
        listenedTime: listenedTime,
        playRecorded: playRecorded,
        completedNaturally: false,
      ));
    }

    _currentSong = song;
    _lastPosition = null;

    if (!isResume) {
      _sessionListenedTime = Duration.zero;
      _sessionTimeAlreadyCached = Duration.zero;
      _sessionPlayRecorded = false;
      print('[StreamingStatsService] New session, reset counters');
    } else {
      print(
          '[StreamingStatsService] Resuming session, listenedTime=${_sessionListenedTime.inSeconds}s, alreadyCached=${_sessionTimeAlreadyCached.inSeconds}s, playRecorded=$_sessionPlayRecorded');
    }

    _scheduleDbFlush();
  }

  /// Called when a song is stopped, paused, skipped, or completed.
  ///
  /// [completedNaturally] should be `true` only when the audio player
  /// reports that the song finished playing to the end. This triggers
  /// the short-song rule (< 30s always counts as 1 play).
  Future<void> onSongStopped({bool completedNaturally = false}) async {
    if (_currentSong == null) {
      print(
          '[StreamingStatsService] onSongStopped called but no current song');
      return;
    }

    print(
        '[StreamingStatsService] Song stopped: ${_currentSong!.title}, completedNaturally=$completedNaturally');

    final song = _currentSong!;
    final listenedTime = _sessionListenedTime;
    final playRecorded = _sessionPlayRecorded;

    await _finalizeSessionForSong(
      song,
      listenedTime: listenedTime,
      playRecorded: playRecorded,
      completedNaturally: completedNaturally,
    );

    _currentSong = null;
    _lastPosition = null;
  }

  // ============================================================================
  // POSITION-BASED TIME TRACKING
  // ============================================================================

  /// Receive position updates from the audio player.
  ///
  /// Call this on every position tick. The service will calculate actual
  /// forward listening progress and ignore seek jumps (> 2s) and backward
  /// movement.
  void updatePosition(Duration position) {
    if (_currentSong == null) return;

    if (_lastPosition != null && position > _lastPosition!) {
      final delta = position - _lastPosition!;
      // Only count forward progress if the jump is small enough to be
      // normal playback. Larger jumps are treated as seeks.
      if (delta <= const Duration(seconds: 2)) {
        _sessionListenedTime += delta;
        _maybeRecordPlay();
      } else {
        print(
            '[StreamingStatsService] Ignored seek jump of ${delta.inSeconds}s');
      }
    }

    _lastPosition = position;
  }

  /// Internal: Check if cumulative listening time has crossed the 30s
  /// threshold and record a play if so.
  void _maybeRecordPlay() {
    if (!_sessionPlayRecorded &&
        (_sessionTimeAlreadyCached + _sessionListenedTime) >=
            const Duration(seconds: 30)) {
      print('[StreamingStatsService] 30s threshold reached, recording play');
      unawaited(_recordPlay());
    }
  }

  // ============================================================================
  // SESSION FINALIZATION
  // ============================================================================

  /// Finalize a specific song session, recording any pending time and
  /// optionally applying the short-song rule.
  Future<void> _finalizeSessionForSong(
    Song song, {
    required Duration listenedTime,
    required bool playRecorded,
    required bool completedNaturally,
  }) async {
    // Short-song rule: any song that completes naturally and is < 30s
    // always counts as 1 play (Spotify-style behaviour).
    if (completedNaturally &&
        song.duration < const Duration(seconds: 30) &&
        !playRecorded) {
      print(
          '[StreamingStatsService] Short song completed naturally (${song.duration.inSeconds}s < 30s), recording play');
      await _recordPlayForSong(song);
      playRecorded = true;
    }

    // Persist any accumulated listening time.
    if (listenedTime > Duration.zero) {
      await _updateStreamingTimeForSong(song, listenedTime);
      _sessionTimeAlreadyCached += listenedTime;
      _sessionListenedTime = Duration.zero;
    }

    await _flushPendingStats();
  }

  // ============================================================================
  // STATS RECORDING
  // ============================================================================

  /// Record a play for the current song session.
  Future<void> _recordPlay() async {
    if (_currentSong == null || _sessionPlayRecorded) return;
    _sessionPlayRecorded = true;
    final song = _currentSong!;
    await _recordPlayForSong(song);
  }

  /// Record a play for a specific song (idempotent within a session).
  Future<void> _recordPlayForSong(Song song) async {
    final songId = song.id;
    final existingStats = _statsCache[songId] ??
        SongStats(
          songId: songId,
          playCount: 0,
          totalTime: Duration.zero,
          firstPlayed: DateTime.now(),
        );

    final updatedStats = existingStats.copyWith(
      playCount: existingStats.playCount + 1,
      lastPlayed: DateTime.now(),
      songTitle: song.title,
      songArtist: song.artist,
      albumId: song.albumId,
      album: song.album,
      albumArtist: song.albumArtist,
    );

    _statsCache[songId] = updatedStats;
    _queueDbWrite(songId, updatedStats);

    _emitTopSongs();
    print(
        '[StreamingStatsService] Play count incremented to ${updatedStats.playCount} for ${song.title}');
  }

  /// Update total streaming time for a specific song.
  Future<void> _updateStreamingTimeForSong(Song song, Duration elapsed) async {
    final songId = song.id;
    final existingStats = _statsCache[songId] ??
        SongStats(
          songId: songId,
          playCount: 0,
          totalTime: Duration.zero,
          firstPlayed: DateTime.now(),
        );

    final newTotalTime = Duration(
      seconds: existingStats.totalTime.inSeconds + elapsed.inSeconds,
    );

    print(
        '[StreamingStatsService] Adding ${elapsed.inSeconds}s to ${song.title} (total: ${newTotalTime.inSeconds}s)');

    final updatedStats = existingStats.copyWith(
      totalTime: newTotalTime,
      lastPlayed: DateTime.now(),
      songTitle: song.title,
      songArtist: song.artist,
      albumId: song.albumId,
      album: song.album,
      albumArtist: song.albumArtist,
    );

    _statsCache[songId] = updatedStats;
    _queueDbWrite(songId, updatedStats);
    _emitTopSongs();
  }

  // ============================================================================
  // DEBOUNCED DATABASE WRITES
  // ============================================================================

  /// Queue a stats update for debounced database write.
  void _queueDbWrite(String songId, SongStats stats) {
    _dirtyStats[songId] = stats;
    _scheduleDbFlush();
  }

  /// Schedule a debounced flush to the database.
  void _scheduleDbFlush() {
    _dbFlushTimer?.cancel();
    _dbFlushTimer = Timer(_dbFlushInterval, () async {
      await _flushPendingStats();
    });
  }

  /// Flush all pending stats to the database immediately.
  Future<void> _flushPendingStats() async {
    if (_isFlushing) return;
    _isFlushing = true;
    _dbFlushTimer?.cancel();

    try {
      if (_dirtyStats.isNotEmpty) {
        final statsToSave = _dirtyStats.values.toList();
        await _database.saveAllStats(statsToSave);
        print(
            '[StreamingStatsService] Flushed ${statsToSave.length} stats to DB');
        _dirtyStats.clear();
      }
    } catch (e) {
      print('[StreamingStatsService] Error flushing stats: $e');
    } finally {
      _isFlushing = false;
    }
  }

  // ============================================================================
  // APP LIFECYCLE OBSERVER
  // ============================================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[StreamingStatsService] App lifecycle: $state');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      // If a song is currently playing, finalize its session immediately so
      // data is not lost if the OS kills the app.
      if (_currentSong != null) {
        final song = _currentSong!;
        final listenedTime = _sessionListenedTime;
        final playRecorded = _sessionPlayRecorded;
        unawaited(_finalizeSessionForSong(
          song,
          listenedTime: listenedTime,
          playRecorded: playRecorded,
          completedNaturally: false,
        ));
        _currentSong = null;
      }
      // Also flush any already-queued dirty stats.
      unawaited(_flushPendingStats());
    }
  }

  @override
  void didChangeAccessibilityFeatures() {}

  @override
  void didChangeLocales(List<Locale>? locales) {}

  @override
  void didChangeMetrics() {}

  @override
  void didChangePlatformBrightness() {}

  @override
  void didChangeTextScaleFactor() {}

  @override
  void didHaveMemoryPressure() {}

  @override
  Future<bool> didPopRoute() => Future<bool>.value(false);

  @override
  Future<bool> didPushRoute(String route) => Future<bool>.value(false);

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) =>
      Future<bool>.value(false);

  @override
  void didChangeViewFocus(ViewFocusEvent event) {}

  @override
  Future<AppExitResponse> didRequestAppExit() async => AppExitResponse.exit;

  @override
  void handleCancelBackGesture() {}

  @override
  void handleCommitBackGesture() {}

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) => false;

  @override
  void handleStatusBarTap() {}

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {}

  // ============================================================================
  // QUERIES & AGGREGATION
  // ============================================================================

  /// Get all stats (from in-memory cache for instant access)
  List<SongStats> getAllStats() {
    return _statsCache.values.where((stat) => stat.playCount > 0).toList();
  }

  /// Get top songs (default 20) from in-memory cache
  List<SongStats> getTopSongs({int limit = 20}) {
    final allStats = getAllStats();
    allStats.sort((a, b) => b.playCount.compareTo(a.playCount));
    return allStats.take(limit).toList();
  }

  /// Get top artists (default 20) aggregated from in-memory cache
  List<ArtistStats> getTopArtists({int limit = 20}) {
    final allStats = getAllStats();
    final Map<String, ArtistStats> artistMap = {};

    for (final songStat in allStats) {
      final artistName =
          songStat.albumArtist ?? songStat.songArtist ?? 'Unknown Artist';

      if (artistMap.containsKey(artistName)) {
        final existing = artistMap[artistName]!;
        final newRandomAlbumId = existing.randomAlbumId ?? songStat.albumId;
        final newRandomSongId = existing.randomSongId ??
            (songStat.albumId == null ? songStat.songId : null);
        artistMap[artistName] = existing.copyWith(
          playCount: existing.playCount + songStat.playCount,
          totalTime: Duration(
              seconds:
                  existing.totalTime.inSeconds + songStat.totalTime.inSeconds),
          lastPlayed: _laterDate(existing.lastPlayed, songStat.lastPlayed),
          firstPlayed: _earlierDate(existing.firstPlayed, songStat.firstPlayed),
          randomAlbumId: newRandomAlbumId,
          randomSongId: newRandomSongId,
          uniqueSongsCount: existing.uniqueSongsCount + 1,
        );
      } else {
        artistMap[artistName] = ArtistStats(
          artistName: artistName,
          playCount: songStat.playCount,
          totalTime: songStat.totalTime,
          firstPlayed: songStat.firstPlayed,
          lastPlayed: songStat.lastPlayed,
          randomAlbumId: songStat.albumId,
          randomSongId: songStat.albumId == null ? songStat.songId : null,
          uniqueSongsCount: 1,
        );
      }
    }

    final artistList = artistMap.values.toList();
    artistList.sort((a, b) => b.totalTime.compareTo(a.totalTime));
    return artistList.take(limit).toList();
  }

  /// Get top albums (default 20) aggregated from in-memory cache
  List<AlbumStats> getTopAlbums({int limit = 20}) {
    final allStats = getAllStats();
    final Map<String, AlbumStats> albumMap = {};

    for (final songStat in allStats) {
      if (songStat.albumId == null || songStat.albumId!.isEmpty) continue;

      final albumId = songStat.albumId!;

      if (albumMap.containsKey(albumId)) {
        final existing = albumMap[albumId]!;
        albumMap[albumId] = existing.copyWith(
          albumArtist: existing.albumArtist ??
              songStat.albumArtist ??
              songStat.songArtist,
          playCount: existing.playCount + songStat.playCount,
          totalTime: Duration(
              seconds:
                  existing.totalTime.inSeconds + songStat.totalTime.inSeconds),
          lastPlayed: _laterDate(existing.lastPlayed, songStat.lastPlayed),
          firstPlayed: _earlierDate(existing.firstPlayed, songStat.firstPlayed),
          uniqueSongsCount: existing.uniqueSongsCount + 1,
        );
      } else {
        albumMap[albumId] = AlbumStats(
          albumId: albumId,
          albumName: songStat.album,
          albumArtist: songStat.albumArtist ?? songStat.songArtist,
          playCount: songStat.playCount,
          totalTime: songStat.totalTime,
          firstPlayed: songStat.firstPlayed,
          lastPlayed: songStat.lastPlayed,
          uniqueSongsCount: 1,
        );
      }
    }

    final albumList = albumMap.values.toList();
    albumList.sort((a, b) => b.totalTime.compareTo(a.totalTime));
    return albumList.take(limit).toList();
  }

  /// Helper: Return the later of two dates
  DateTime? _laterDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// Helper: Return the earlier of two dates
  DateTime? _earlierDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
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

  /// Get average daily listening time
  ({Duration perCalendarDay, Duration perActiveDay, int activeDays})
      getAverageDailyTime() {
    final stats = getTotalStats();
    if (stats.totalSongsPlayed == 0) {
      return (
        perCalendarDay: Duration.zero,
        perActiveDay: Duration.zero,
        activeDays: 0,
      );
    }

    final allStats = getAllStats();
    if (allStats.isEmpty) {
      return (
        perCalendarDay: Duration.zero,
        perActiveDay: Duration.zero,
        activeDays: 0,
      );
    }

    DateTime? firstPlayed;
    DateTime? lastPlayed;
    final Set<String> uniqueDates = {};

    for (final stat in allStats) {
      if (stat.firstPlayed != null) {
        if (firstPlayed == null || stat.firstPlayed!.isBefore(firstPlayed)) {
          firstPlayed = stat.firstPlayed;
        }
      }
      if (stat.lastPlayed != null) {
        if (lastPlayed == null || stat.lastPlayed!.isAfter(lastPlayed)) {
          lastPlayed = stat.lastPlayed;
        }
        final dateKey =
            '${stat.lastPlayed!.year}-${stat.lastPlayed!.month}-${stat.lastPlayed!.day}';
        uniqueDates.add(dateKey);
      }
    }

    if (firstPlayed == null || lastPlayed == null) {
      return (
        perCalendarDay: Duration.zero,
        perActiveDay: Duration.zero,
        activeDays: 0,
      );
    }

    final daysSinceStart = lastPlayed.difference(firstPlayed).inDays + 1;
    final perCalendarDay = daysSinceStart > 0
        ? Duration(
            seconds:
                (stats.totalTimeStreamed.inSeconds / daysSinceStart).round())
        : stats.totalTimeStreamed;

    final activeDaysCount = uniqueDates.length;
    final perActiveDay = activeDaysCount > 0
        ? Duration(
            seconds:
                (stats.totalTimeStreamed.inSeconds / activeDaysCount).round())
        : Duration.zero;

    return (
      perCalendarDay: perCalendarDay,
      perActiveDay: perActiveDay,
      activeDays: activeDaysCount,
    );
  }

  /// Reset all statistics
  Future<void> resetAllStats() async {
    print('[StreamingStatsService] Resetting all stats');
    _statsCache.clear();
    _dirtyStats.clear();
    await _database.resetAllStats();
    _emitTopSongs();
    notifyListeners();
  }

  /// Reload stats from database into memory cache (after import)
  Future<void> reloadFromDatabase() async {
    print('[StreamingStatsService] Reloading stats from database');
    _statsCache.clear();
    _dirtyStats.clear();
    final allStats = await _database.getAllStats();
    for (final stat in allStats) {
      _statsCache[stat.songId] = stat;
    }
    _emitTopSongs();
    _emitTopArtists();
    _emitTopAlbums();
    notifyListeners();
    print(
        '[StreamingStatsService] Reloaded ${_statsCache.length} songs from database');
  }

  /// Get stats for a specific song from in-memory cache
  SongStats? getSongStats(String songId) {
    return _statsCache[songId];
  }

  /// Emit updated top songs to stream
  void _emitTopSongs() {
    final topSongs = getTopSongs();
    print(
        '[StreamingStatsService] _emitTopSongs: emitting ${topSongs.length} songs to stream');
    if (topSongs.isNotEmpty) {
      print(
          '[StreamingStatsService] Top song: ${topSongs.first.songTitle} (${topSongs.first.playCount} plays)');
    }
    _topSongsStreamController.add(topSongs);
    _emitTopArtists();
    _emitTopAlbums();
    notifyListeners();
  }

  /// Emit updated top artists to stream
  void _emitTopArtists() {
    final topArtists = getTopArtists();
    _topArtistsStreamController.add(topArtists);
  }

  /// Emit updated top albums to stream
  void _emitTopAlbums() {
    final topAlbums = getTopAlbums();
    _topAlbumsStreamController.add(topAlbums);
  }

  /// Public refresh method for UI to request updated stats
  void refreshTopSongs() {
    _emitTopSongs();
  }

  // ============================================================================
  // TEST HELPERS
  // ============================================================================

  /// Reset internal state for unit tests. Do not use in production code.
  @visibleForTesting
  void resetForTests() {
    _dbFlushTimer?.cancel();
    _currentSong = null;
    _sessionListenedTime = Duration.zero;
    _sessionTimeAlreadyCached = Duration.zero;
    _sessionPlayRecorded = false;
    _lastPosition = null;
    _dirtyStats.clear();
    _isFlushing = false;
    _statsCache.clear();
  }

  /// Flush pending stats immediately for unit tests.
  @visibleForTesting
  Future<void> flushForTests() async {
    await _flushPendingStats();
  }

  @override
  void dispose() {
    _dbFlushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _topSongsStreamController.close();
    _topArtistsStreamController.close();
    _topAlbumsStreamController.close();
    super.dispose();
  }
}
