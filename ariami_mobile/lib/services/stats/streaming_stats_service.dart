import 'dart:async';
import 'dart:ui' show AppExitResponse, ViewFocusEvent;

import 'package:ariami_core/ariami_core.dart'
    show ListeningEvent, ListeningEventTracker, ListeningTrackInfo;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../models/song_stats.dart';
import '../../models/artist_stats.dart';
import '../../models/album_stats.dart';
import '../../database/stats_database.dart';
import '../song_id_remapping_service.dart';

/// Service for tracking streaming statistics across the app with SQLite persistence.
///
/// The play/time rules live in the shared core [ListeningEventTracker]
/// (mobile configuration: 15s checkpoints, trusted forward jumps for
/// coalesced background position updates, session-driven restarts). This
/// service adapts the app's playback-session callbacks onto the tracker and
/// consumes its honest [ListeningEvent]s twice: applied to the local
/// per-device SQLite stats, and mirrored to the account pipeline — so the
/// two can never disagree about what counted.
///
/// Key behaviours (all enforced by the shared tracker):
/// - A "play" is counted once per play-action when cumulative listening time
///   reaches 30s or half the track, whichever is smaller.
/// - Cumulative time persists across pause/resume within the same play-action.
/// - Short songs (< 30s) that complete naturally always count as 1 play.
/// - Time is tracked via audio position updates to avoid inflating stats during
///   buffering, loading, or seeks.
/// - Database writes are debounced (5s) to reduce SQLite pressure.
/// - Stats are flushed immediately when the app is backgrounded or killed.
class StreamingStatsService extends ChangeNotifier
    implements WidgetsBindingObserver {
  // Singleton pattern
  static final StreamingStatsService _instance =
      StreamingStatsService._internal();

  factory StreamingStatsService() => _instance;

  StreamingStatsService._internal();

  // Dependencies
  late StatsDatabase _database;
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  // In-memory cache for instant UI updates
  final Map<String, SongStats> _statsCache = {};

  /// Account-wide stats overlay (server rollups merged with this device's
  /// pending uploads), maintained by AccountStatsService. When present, read
  /// queries and streams show the whole account across devices; the local
  /// per-device tracking underneath is unaffected and keeps recording.
  Map<String, SongStats>? _accountOverlay;

  /// Sink for cross-device listening events (wired by AccountStatsService).
  /// Every credited play and time segment is mirrored here so it can be
  /// queued for idempotent upload to the server.
  void Function(ListeningEvent event)? onListeningEvent;

  // ============================================================================
  // SESSION STATE
  // ============================================================================

  /// The song currently being tracked (actively playing).
  Song? _currentSong;

  /// Uncommitted listening is committed to the stats this often, so a killed
  /// app loses at most this much credit.
  static const int _checkpointIntervalMs = 15000;

  /// The shared rule engine. Every emitted event updates the local SQLite
  /// stats and is mirrored to the account pipeline.
  ///
  /// Mobile configuration: background playback coalesces position updates,
  /// so large forward jumps while playing are genuine audio (explicit seeks
  /// arrive via [markPositionDiscontinuity]), and the playback manager drives
  /// restarts/repeat-one itself through [onSongStarted]/[onSongStopped], so
  /// engine-level restart detection stays off.
  ListeningEventTracker? _engineInstance;
  ListeningEventTracker get _engine =>
      _engineInstance ??= ListeningEventTracker(
        onEvent: _onEngineEvent,
        checkpointMs: _checkpointIntervalMs,
        trustPlayingForwardJumps: true,
        detectRestarts: false,
        clientKind: 'mobile',
      );

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
  Future<void> initialize() {
    if (_isInitialized) return Future<void>.value();
    final inFlight = _initializationFuture;
    if (inFlight != null) return inFlight;

    final future = _initialize();
    _initializationFuture = future;
    return future.whenComplete(() {
      if (!_isInitialized && identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    });
  }

  Future<void> _initialize() async {
    // On-listen emissions are deferred a microtask: subscriptions happen
    // during build (StreamBuilder.initState), and emitting synchronously
    // notifies listeners mid-build, which Flutter flags in debug mode.
    _topSongsStreamController = StreamController<List<SongStats>>.broadcast(
      onListen: () => scheduleMicrotask(_emitTopSongs),
    );

    _topArtistsStreamController = StreamController<List<ArtistStats>>.broadcast(
      onListen: () => scheduleMicrotask(_emitTopArtists),
    );

    _topAlbumsStreamController = StreamController<List<AlbumStats>>.broadcast(
      onListen: () => scheduleMicrotask(_emitTopAlbums),
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
    _isInitialized = true;
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

    // A non-resume start is a new play-action even for the same song
    // (restart / repeat-one), so end the previous one first. Track changes
    // finalize the old action inside the engine either way.
    if (!isResume) {
      _engine.stop();
    }
    _engine.onTrackChanged(ListeningTrackInfo(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      albumId: song.albumId,
      album: song.album,
      albumArtist: song.albumArtist,
      durationMs: song.duration.inMilliseconds,
    ));
    _engine.onPlayingChanged(true);

    _currentSong = song;
    _scheduleDbFlush();
  }

  /// Called when a song is stopped, paused, skipped, or completed.
  ///
  /// [completedNaturally] should be `true` only when the audio player
  /// reports that the song finished playing to the end. This triggers
  /// the short-song rule (< 30s always counts as 1 play).
  Future<void> onSongStopped({bool completedNaturally = false}) async {
    if (_currentSong == null) {
      print('[StreamingStatsService] onSongStopped called but no current song');
      return;
    }

    print(
        '[StreamingStatsService] Song stopped: ${_currentSong!.title}, completedNaturally=$completedNaturally');

    if (completedNaturally) {
      _engine.onTrackCompleted();
    }
    // Pausing commits pending listening time while keeping the play-action
    // resumable (a following onSongStarted(isResume: true) continues it).
    _engine.onPlayingChanged(false);

    _currentSong = null;
    await _flushPendingStats();
  }

  // ============================================================================
  // POSITION-BASED TIME TRACKING
  // ============================================================================

  /// Receive position updates from the audio player.
  ///
  /// Call this on every position tick. The engine credits genuine forward
  /// audio progress and ignores explicit seeks and backward movement.
  void updatePosition(Duration position) {
    if (_currentSong == null) return;
    _engine.onPositionTick(position.inMilliseconds);
  }

  /// Update whether the player is actively advancing audio.
  ///
  /// This catches play/pause changes from lock-screen/notification controls,
  /// where PlaybackManager may not receive the original button event.
  void setPlaybackActive(bool isActive) {
    _engine.onPlayingChanged(isActive);
    if (!isActive) {
      unawaited(_flushPendingStats());
    }
  }

  /// Reset the stats baseline after a seek or other explicit position jump.
  void markPositionDiscontinuity() {
    _engine.onSeek();
  }

  // ============================================================================
  // ENGINE EVENTS → LOCAL STATS + ACCOUNT PIPELINE
  // ============================================================================

  /// Consumes each honest event from the shared engine: applied to the local
  /// per-device stats and mirrored to the account pipeline (a no-op until
  /// AccountStatsService wires [onListeningEvent]).
  void _onEngineEvent(ListeningEvent event) {
    _applyEventToLocalStats(event);
    onListeningEvent?.call(event);
  }

  void _applyEventToLocalStats(ListeningEvent event) {
    final songId = event.songId;
    final existingStats = _statsCache[songId] ??
        SongStats(
          songId: songId,
          playCount: 0,
          totalTime: Duration.zero,
          firstPlayed: DateTime.now(),
        );

    final updatedStats = existingStats.copyWith(
      playCount: existingStats.playCount + event.plays,
      totalTime: Duration(
        seconds: existingStats.totalTime.inSeconds + event.listenedMs ~/ 1000,
      ),
      lastPlayed: DateTime.now(),
      songTitle: event.songTitle,
      songArtist: event.songArtist,
      albumId: event.albumId,
      album: event.album,
      albumArtist: event.albumArtist,
    );

    _statsCache[songId] = updatedStats;
    _queueDbWrite(songId, updatedStats);
    _emitTopSongs();
    if (event.plays > 0) {
      print(
          '[StreamingStatsService] Play count incremented to ${updatedStats.playCount} for ${event.songTitle}');
    }
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
      // If a song is currently playing, commit its accumulated time
      // immediately so data is not lost if the OS kills the app. Keep the
      // session active: background playback can continue to emit position
      // updates, and clearing the current song here would drop the rest of the
      // listen until playback is explicitly restarted.
      if (_currentSong != null) {
        _engine.flush();
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

  /// Get all stats for display. When the account overlay is active this is
  /// the whole account across devices; otherwise this device's local stats.
  List<SongStats> getAllStats() {
    final overlay = _accountOverlay;
    if (overlay != null) {
      return overlay.values.where((stat) => stat.playCount > 0).toList();
    }
    return _statsCache.values.where((stat) => stat.playCount > 0).toList();
  }

  /// This device's own tracked stats, ignoring the account overlay. Used for
  /// the one-time baseline import and for export.
  List<SongStats> getLocalDeviceStats() {
    return _statsCache.values.where((stat) => stat.playCount > 0).toList();
  }

  /// Whether queries currently reflect the whole account (all devices).
  bool get isShowingAccountStats => _accountOverlay != null;

  /// Sets (or clears, with null) the account-wide stats overlay and refreshes
  /// every stream/listener. Called by AccountStatsService whenever the server
  /// summary or the pending-upload queue changes.
  void setAccountStatsOverlay(List<SongStats>? stats) {
    if (stats == null) {
      if (_accountOverlay == null) return;
      _accountOverlay = null;
    } else {
      _accountOverlay = {for (final stat in stats) stat.songId: stat};
    }
    _emitTopSongs();
    notifyListeners();
  }

  /// Get top songs from in-memory cache; every song unless [limit] is given.
  List<SongStats> getTopSongs({int? limit}) {
    final allStats = getAllStats();
    allStats.sort((a, b) => b.playCount.compareTo(a.playCount));
    return limit == null ? allStats : allStats.take(limit).toList();
  }

  /// Get top artists aggregated from in-memory cache; every artist unless
  /// [limit] is given.
  ///
  /// Artists are grouped by a normalized key (see [_normalizeArtistKey]) so the
  /// same artist coming from different sources — e.g. a standalone single and an
  /// album, which may store the name with different casing, whitespace or dash
  /// characters — collapses into a single entry instead of appearing twice.
  List<ArtistStats> getTopArtists({int? limit}) {
    final allStats = getAllStats();
    final Map<String, ArtistStats> artistMap = {};
    // Tracks the best display name (highest contributing play count) per key so
    // we show a properly-cased label rather than whichever variant arrived first.
    final Map<String, int> displayNamePlayCount = {};

    for (final songStat in allStats) {
      final rawName = _cleanArtistName(
          songStat.albumArtist ?? songStat.songArtist ?? 'Unknown Artist');
      final key = _normalizeArtistKey(rawName);

      if (artistMap.containsKey(key)) {
        final existing = artistMap[key]!;
        final newRandomAlbumId = existing.randomAlbumId ?? songStat.albumId;
        final newRandomSongId = existing.randomSongId ??
            (songStat.albumId == null ? songStat.songId : null);
        // Prefer the name variant with the most plays for display.
        final keepName = songStat.playCount > (displayNamePlayCount[key] ?? 0)
            ? rawName
            : existing.artistName;
        if (songStat.playCount > (displayNamePlayCount[key] ?? 0)) {
          displayNamePlayCount[key] = songStat.playCount;
        }
        artistMap[key] = existing.copyWith(
          artistName: keepName,
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
        displayNamePlayCount[key] = songStat.playCount;
        artistMap[key] = ArtistStats(
          artistName: rawName,
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
    return limit == null ? artistList : artistList.take(limit).toList();
  }

  /// Matches invisible characters that should never affect artist identity:
  /// C0/C1 control codes (including the stray NUL terminators some server-side
  /// tag readers leave on strings read from file metadata), plus zero-width and
  /// BOM format characters.
  static final RegExp _invisibleChars = RegExp(
      '[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028\u2029\u2060\ufeff]');

  /// Strip invisible characters and surrounding whitespace from an artist name,
  /// preserving its original casing/spacing for display.
  String _cleanArtistName(String name) =>
      name.replaceAll(_invisibleChars, '').trim();

  /// Normalize an artist name into a stable grouping key so visually-identical
  /// names from different sources match. Removes invisible characters,
  /// lowercases, trims, collapses internal whitespace, and unifies the various
  /// unicode hyphen/dash characters to a plain hyphen.
  String _normalizeArtistKey(String name) {
    var s = name.replaceAll(_invisibleChars, '').trim().toLowerCase();
    // Map unicode hyphen/dash variants (hyphen, non-breaking hyphen, figure
    // dash, en/em dash, minus sign) to a plain ASCII hyphen.
    s = s.replaceAll(RegExp('[\u2010-\u2015\u2212]'), '-');
    // Collapse any run of whitespace to a single space.
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  /// Get top albums aggregated from in-memory cache; every album unless
  /// [limit] is given.
  List<AlbumStats> getTopAlbums({int? limit}) {
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
    return limit == null ? albumList : albumList.take(limit).toList();
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

  /// Remap stale song IDs and optionally repair album metadata in persisted
  /// stats using current library data.
  ///
  /// SongStats are keyed by songId, which is MD5(filePath) on the server. When
  /// the music library is moved to a different folder, every songId changes,
  /// leaving the stats database with rows that no longer correspond to any
  /// song in the library. Those stale rows still display in the per-track view
  /// (each shows its own correct count), but artist/album aggregations sum
  /// every row keyed by artist/album name, double-counting plays for songs
  /// that ended up with multiple ids across library moves or imports.
  ///
  /// This method:
  ///   1. Walks the in-memory stats cache and asks
  ///      [SongIdRemappingService.remapStats] to match stale songIds to the
  ///      current library by title + artist.
  ///   2. Merges any stats that collapse onto the same songId — including the
  ///      common case where a stale entry from a prior path co-exists with a
  ///      fresh entry recorded under the new path.
  ///   3. Persists the remapped/merged set, replacing the previous DB
  ///      contents so stale rows are removed rather than left behind.
  ///
  /// Returns the number of stat rows that were dropped (remapped onto an
  /// existing entry); metadata-only repairs return 0.
  Future<int> remapStaleStatIdsFromLibrary(
    List<SongModel> librarySongs, {
    List<AlbumModel> libraryAlbums = const <AlbumModel>[],
  }) async {
    if (!_isInitialized) return 0;
    if (librarySongs.isEmpty) return 0;

    final originalStats = _statsCache.values.toList();
    if (originalStats.isEmpty) return 0;

    // Flush any pending in-flight writes before we rewrite the table.
    await _flushPendingStats();

    final remapped = SongIdRemappingService().remapStats(
      originalStats,
      librarySongs,
    );

    final repaired = _repairAlbumMetadata(
      remapped,
      librarySongs: librarySongs,
      libraryAlbums: libraryAlbums,
    );

    // Both helpers return the original list reference when nothing changed.
    if (identical(remapped, originalStats) && identical(repaired, remapped)) {
      return 0;
    }

    final droppedCount = originalStats.length - repaired.length;

    _statsCache
      ..clear()
      ..addEntries(repaired.map((s) => MapEntry(s.songId, s)));
    _dirtyStats.clear();

    await _database.resetAllStats();
    if (repaired.isNotEmpty) {
      await _database.saveAllStats(repaired);
    }

    _emitTopSongs();
    notifyListeners();

    print('[StreamingStatsService] Remapped stale stat IDs: '
        '${originalStats.length} rows -> ${repaired.length} rows '
        '($droppedCount merged)');

    return droppedCount;
  }

  List<SongStats> _repairAlbumMetadata(
    List<SongStats> stats, {
    required List<SongModel> librarySongs,
    required List<AlbumModel> libraryAlbums,
  }) {
    if (libraryAlbums.isEmpty) return stats;

    final albumsById = <String, AlbumModel>{
      for (final album in libraryAlbums) album.id: album,
    };
    final songAlbumIds = <String, String>{
      for (final song in librarySongs)
        if (song.albumId != null) song.id: song.albumId!,
    };
    List<SongStats>? repaired;

    for (var index = 0; index < stats.length; index++) {
      final stat = stats[index];
      final albumId = stat.albumId ?? songAlbumIds[stat.songId];
      final album = albumId == null ? null : albumsById[albumId];
      if (album == null) continue;

      final next = stat.copyWith(
        albumId: albumId,
        album: stat.album?.trim().isNotEmpty == true ? stat.album : album.title,
        albumArtist: stat.albumArtist?.trim().isNotEmpty == true
            ? stat.albumArtist
            : album.artist,
      );
      if (next.albumId == stat.albumId &&
          next.album == stat.album &&
          next.albumArtist == stat.albumArtist) {
        continue;
      }
      repaired ??= List<SongStats>.from(stats);
      repaired[index] = next;
    }

    return repaired ?? stats;
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

  /// Get stats for a specific song (account-wide when the overlay is active)
  SongStats? getSongStats(String songId) {
    return _accountOverlay?[songId] ?? _statsCache[songId];
  }

  /// Emit updated top songs to stream
  void _emitTopSongs() {
    if (_topSongsStreamController.isClosed) return;
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
    if (_topArtistsStreamController.isClosed) return;
    final topArtists = getTopArtists();
    _topArtistsStreamController.add(topArtists);
  }

  /// Emit updated top albums to stream
  void _emitTopAlbums() {
    if (_topAlbumsStreamController.isClosed) return;
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
    _engineInstance = null; // a fresh engine, so no play-action carries over
    _dirtyStats.clear();
    _isFlushing = false;
    _statsCache.clear();
    _accountOverlay = null;
    onListeningEvent = null;
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
