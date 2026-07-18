import 'dart:io';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/credited_artist_splitter.dart';
import 'package:sqlite3/sqlite3.dart';

part 'listening_stats_store/event_ingestion.dart';
part 'listening_stats_store/queries.dart';
part 'listening_stats_store/rollup_maintenance.dart';
part 'listening_stats_store/schema.dart';

/// Server-side store for per-user listening statistics.
///
/// Raw events are the source of truth: every accepted [ListeningEvent] is kept
/// in `listening_events`, keyed by its client-generated eventId, so uploads are
/// idempotent (retries and offline replays can never double-count) and every
/// rollup table (song, credited artist, album, daily) is disposable and can
/// always be rebuilt from scratch.
///
/// Trust model: the caller derives `userId`/`deviceId` from a validated
/// session — nothing in the event payload identifies the user.
class ListeningStatsStore {
  ListeningStatsStore({required this.databasePath});

  final String databasePath;
  Database? _database;
  final CreditedArtistSplitter _splitter = CreditedArtistSplitter();

  /// Version of the derived-rollup schema. When a database written by older
  /// code (or a fresh file) reports a lower version, the derived tables are
  /// rebuilt from the raw event log on startup. Bump this whenever derivation
  /// logic or derived-table shapes change.
  static const int rollupSchemaVersion = 2;

  /// dim values used in `listening_daily_rollups`.
  static const String dimTotal = 'total';
  static const String dimSong = 'song';
  static const String dimArtist = 'artist';
  static const String dimAlbum = 'album';

  /// Sanity cap for a single event's listened time. Clients checkpoint every
  /// ~30s, so anything above 6h in one event is a corrupt or hostile payload.
  static const int maxListenedMsPerEvent = 6 * 60 * 60 * 1000;

  /// Baseline imports may carry a device's whole history in one event.
  static const int maxListenedMsPerBaselineEvent =
      5 * 365 * 24 * 60 * 60 * 1000;
  static const int maxPlaysPerBaselineEvent = 1000000;

  /// Max events accepted per upload call.
  static const int maxEventsPerBatch = 500;

  bool get isInitialized => _database != null;

  Database get _db {
    final db = _database;
    if (db == null) {
      throw StateError(
        'ListeningStatsStore is not initialized. Call initialize() first.',
      );
    }
    return db;
  }

  /// Opens the database file and creates the schema if needed. Idempotent.
  void initialize() => _initializeStore();

  /// Applies a batch of events for [userId] from [deviceId].
  ///
  /// Returns how many events were newly accepted vs. recognized duplicates.
  /// Duplicates (same eventId, or a play whose playId already counted) are
  /// acknowledged as applied so clients can safely drop them from their
  /// outbox.
  ({int accepted, int duplicates, int rejected}) applyEvents(
    String userId,
    String deviceId,
    List<ListeningEvent> events,
  ) =>
      _applyEvents(userId, deviceId, events);

  /// Account-wide summary for [userId], one rollup per song.
  ListeningStatsSummary getSummary(String userId) => _getSummary(userId);

  /// Listened milliseconds per local day (`yyyy-mm-dd`) over the last [days]
  /// days, grouped by the listener's local day at the time of each event.
  Map<String, int> getDailyListenedMs(String userId, {int days = 120}) =>
      _getDailyListenedMs(userId, days: days);

  /// Per-song listening totals within the trailing [days] window, newest
  /// activity first. Baseline imports are excluded.
  List<ListeningSongRollup> getRecentSongTotals(
    String userId, {
    int days = 7,
  }) =>
      _getRecentSongTotals(userId, days: days);

  /// Aggregated stats for an inclusive local-day range. Baseline imports never
  /// appear here. A non-positive [limit] returns every ranked entry.
  ListeningPeriodStats getPeriodStats(
    String userId, {
    required String fromDay,
    required String toDay,
    int limit = 50,
  }) =>
      _getPeriodStats(
        userId,
        fromDay: fromDay,
        toDay: toDay,
        limit: limit,
      );

  /// Top credited artists: all-time when [days] is null, otherwise a trailing
  /// window of that many local days (today inclusive) from the daily grain.
  /// A non-positive [limit] returns every artist.
  List<ListeningArtistRollup> getTopArtists(
    String userId, {
    int? days,
    int limit = 100,
  }) =>
      _getTopArtists(userId, days: days, limit: limit);

  /// Top albums: all-time when [days] is null, otherwise a trailing window of
  /// that many local days (today inclusive) from the daily grain.
  /// A non-positive [limit] returns every album.
  List<ListeningAlbumRollup> getTopAlbums(
    String userId, {
    int? days,
    int limit = 100,
  }) =>
      _getTopAlbums(userId, days: days, limit: limit);

  /// Per-local-day plays + listened time over the trailing [days] window,
  /// baseline-free. The listened-ms values match [getDailyListenedMs].
  Map<String, ListeningDailyTotal> getDailyTotals(
    String userId, {
    int days = 120,
  }) =>
      _getDailyTotals(userId, days: days);

  /// Deletes all listening data for [userId].
  void resetUser(String userId) => _resetUser(userId);

  /// Recomputes all of [userId]'s rollups from the raw event log.
  void rebuildRollups(String userId) => _rebuildRollups(userId);

  void close() {
    _database?.close();
    _database = null;
  }
}
