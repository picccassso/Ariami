import 'dart:io';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:sqlite3/sqlite3.dart';

/// Server-side store for per-user listening statistics.
///
/// Raw events are the source of truth: every accepted [ListeningEvent] is kept
/// in `listening_events`, keyed by its client-generated eventId, so uploads are
/// idempotent (retries and offline replays can never double-count) and the
/// per-song rollups can always be rebuilt from scratch.
///
/// Trust model: the caller derives `userId`/`deviceId` from a validated
/// session — nothing in the event payload identifies the user.
class ListeningStatsStore {
  ListeningStatsStore({required this.databasePath});

  final String databasePath;
  Database? _database;

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
  void initialize() {
    if (_database != null) return;

    final parentDirectory = File(databasePath).parent;
    if (!parentDirectory.existsSync()) {
      parentDirectory.createSync(recursive: true);
    }

    final db = sqlite3.open(databasePath);
    try {
      db.execute('PRAGMA journal_mode=WAL;');
      db.execute('PRAGMA synchronous=NORMAL;');
      db.execute('PRAGMA busy_timeout=5000;');
      _createSchema(db);
      _database = db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_events (
        event_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        play_id TEXT,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        plays INTEGER NOT NULL DEFAULT 0,
        occurred_at INTEGER NOT NULL,
        tz_offset_min INTEGER NOT NULL DEFAULT 0,
        received_at INTEGER NOT NULL,
        song_title TEXT,
        song_artist TEXT,
        album_id TEXT,
        album TEXT,
        album_artist TEXT
      )
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_events_user_song
        ON listening_events (user_id, song_id)
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_events_user_time
        ON listening_events (user_id, occurred_at)
    ''');
    // Second line of defence against double-counted plays: even if a buggy
    // client re-sends the same play-action under a fresh eventId, only one
    // play per (user, playId) can ever land.
    db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_listening_events_play_once
        ON listening_events (user_id, play_id)
        WHERE plays > 0 AND play_id IS NOT NULL
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_song_rollups (
        user_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        play_count INTEGER NOT NULL DEFAULT 0,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        first_played INTEGER,
        last_played INTEGER,
        song_title TEXT,
        song_artist TEXT,
        album_id TEXT,
        album TEXT,
        album_artist TEXT,
        PRIMARY KEY (user_id, song_id)
      )
    ''');
  }

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
  ) {
    if (events.isEmpty) return (accepted: 0, duplicates: 0, rejected: 0);

    var accepted = 0;
    var duplicates = 0;
    var rejected = 0;
    final receivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;

    final db = _db;
    db.execute('BEGIN IMMEDIATE');
    try {
      final insertEvent = db.prepare('''
        INSERT OR IGNORE INTO listening_events (
          event_id, user_id, device_id, song_id, play_id, listened_ms, plays,
          occurred_at, tz_offset_min, received_at,
          song_title, song_artist, album_id, album, album_artist
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      final findPlay = db.prepare('''
        SELECT 1 FROM listening_events
        WHERE user_id = ? AND play_id = ? AND plays > 0
        LIMIT 1
      ''');
      try {
        for (final raw in events.take(maxEventsPerBatch)) {
          final event = _sanitize(raw);
          if (event == null) {
            rejected++;
            continue;
          }

          // Baseline events describe a device's imported historical state and
          // may legitimately change (the user restores an older backup on the
          // device). They replace rather than accumulate.
          if (event.eventId.startsWith('baseline:')) {
            switch (_applyBaselineEvent(db, userId, deviceId, event,
                receivedAt: receivedAt)) {
              case _BaselineOutcome.accepted:
                accepted++;
              case _BaselineOutcome.duplicate:
                duplicates++;
              case _BaselineOutcome.rejected:
                rejected++;
            }
            continue;
          }

          // A play whose play-action already counted (e.g. a retry that was
          // assigned a new eventId) is stored with its plays zeroed so the
          // event log itself stays double-count-free for rebuilds.
          var plays = event.plays;
          if (plays > 0 && event.playId != null) {
            final rows = findPlay.select([userId, event.playId]);
            if (rows.isNotEmpty) {
              plays = 0;
            }
          }

          insertEvent.execute([
            event.eventId,
            userId,
            deviceId,
            event.songId,
            event.playId,
            event.listenedMs,
            plays,
            event.occurredAtMs,
            event.tzOffsetMinutes,
            receivedAt,
            event.songTitle,
            event.songArtist,
            event.albumId,
            event.album,
            event.albumArtist,
          ]);

          if (db.updatedRows == 0) {
            duplicates++;
            continue;
          }

          _applyToRollup(db, userId, event, plays);
          accepted++;
        }
      } finally {
        insertEvent.close();
        findPlay.close();
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }

    return (accepted: accepted, duplicates: duplicates, rejected: rejected);
  }

  /// Applies a baseline event with replace semantics.
  ///
  /// Unlike normal events (append-only, first write wins), a device's
  /// baseline for a song is state: re-importing an old backup on that device
  /// re-uploads the same deterministic eventId with different totals, and the
  /// account should reflect the restored history. Ownership is enforced from
  /// the session-derived user/device — an eventId that exists under another
  /// user or device is rejected, never overwritten.
  _BaselineOutcome _applyBaselineEvent(
    Database db,
    String userId,
    String deviceId,
    ListeningEvent event, {
    required int receivedAt,
  }) {
    final existing = db.select(
      'SELECT user_id, device_id, song_id, listened_ms, plays '
      'FROM listening_events WHERE event_id = ?',
      [event.eventId],
    );

    if (existing.isEmpty) {
      db.execute('''
        INSERT INTO listening_events (
          event_id, user_id, device_id, song_id, play_id, listened_ms, plays,
          occurred_at, tz_offset_min, received_at,
          song_title, song_artist, album_id, album, album_artist
        ) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        event.eventId,
        userId,
        deviceId,
        event.songId,
        event.listenedMs,
        event.plays,
        event.occurredAtMs,
        event.tzOffsetMinutes,
        receivedAt,
        event.songTitle,
        event.songArtist,
        event.albumId,
        event.album,
        event.albumArtist,
      ]);
      _applyToRollup(db, userId, event, event.plays);
      return _BaselineOutcome.accepted;
    }

    final row = existing.first;
    if (row['user_id'] != userId ||
        row['device_id'] != deviceId ||
        row['song_id'] != event.songId) {
      return _BaselineOutcome.rejected;
    }
    if (row['listened_ms'] == event.listenedMs && row['plays'] == event.plays) {
      return _BaselineOutcome.duplicate;
    }

    db.execute('''
      UPDATE listening_events SET
        listened_ms = ?, plays = ?, occurred_at = ?, tz_offset_min = ?,
        received_at = ?,
        song_title = COALESCE(?, song_title),
        song_artist = COALESCE(?, song_artist),
        album_id = COALESCE(?, album_id),
        album = COALESCE(?, album),
        album_artist = COALESCE(?, album_artist)
      WHERE event_id = ?
    ''', [
      event.listenedMs,
      event.plays,
      event.occurredAtMs,
      event.tzOffsetMinutes,
      receivedAt,
      event.songTitle,
      event.songArtist,
      event.albumId,
      event.album,
      event.albumArtist,
      event.eventId,
    ]);
    _recomputeRollupForSong(db, userId, event.songId);
    return _BaselineOutcome.accepted;
  }

  /// Recomputes one (user, song) rollup row from the raw event log — the
  /// incremental math after a baseline replacement isn't just additive.
  void _recomputeRollupForSong(Database db, String userId, String songId) {
    db.execute(
      'DELETE FROM listening_song_rollups WHERE user_id = ? AND song_id = ?',
      [userId, songId],
    );
    db.execute('''
      INSERT INTO listening_song_rollups (
        user_id, song_id, play_count, listened_ms, first_played, last_played,
        song_title, song_artist, album_id, album, album_artist
      )
      SELECT
        user_id, song_id, SUM(plays), SUM(listened_ms),
        MIN(occurred_at), MAX(occurred_at),
        MAX(song_title), MAX(song_artist), MAX(album_id), MAX(album),
        MAX(album_artist)
      FROM listening_events
      WHERE user_id = ? AND song_id = ?
      GROUP BY user_id, song_id
    ''', [userId, songId]);
  }

  /// Validates bounds and normalizes an incoming event. Returns null when the
  /// event is malformed beyond repair.
  ListeningEvent? _sanitize(ListeningEvent event) {
    if (event.eventId.isEmpty || event.eventId.length > 128) return null;
    if (event.songId.isEmpty || event.songId.length > 256) return null;
    if (event.listenedMs < 0 || event.plays < 0) return null;

    final isBaseline = event.eventId.startsWith('baseline:');
    final maxListened =
        isBaseline ? maxListenedMsPerBaselineEvent : maxListenedMsPerEvent;
    final maxPlays = isBaseline ? maxPlaysPerBaselineEvent : 1;
    var listenedMs = event.listenedMs;
    var plays = event.plays;
    if (listenedMs > maxListened) listenedMs = maxListened;
    if (plays > maxPlays) plays = maxPlays;
    if (listenedMs == 0 && plays == 0) return null;

    // Clamp obviously-wrong client clocks (more than a day in the future) to
    // the server's now, so a device with a broken clock can't write events
    // "from 2099" that pollute daily rollups forever.
    var occurredAt = event.occurredAtMs;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (occurredAt > now + Duration.millisecondsPerDay || occurredAt <= 0) {
      occurredAt = now;
    }

    var tzOffset = event.tzOffsetMinutes;
    if (tzOffset < -14 * 60 || tzOffset > 14 * 60) tzOffset = 0;

    // If the song duration is known, one segment can't credit more than the
    // full track plus a small tolerance.
    final duration = event.songDurationMs;
    if (!isBaseline &&
        duration != null &&
        duration > 0 &&
        listenedMs > duration + 5000) {
      listenedMs = duration + 5000;
    }

    return ListeningEvent(
      eventId: event.eventId,
      songId: event.songId,
      playId: event.playId,
      listenedMs: listenedMs,
      plays: plays,
      occurredAtMs: occurredAt,
      tzOffsetMinutes: tzOffset,
      songTitle: _truncate(event.songTitle, 512),
      songArtist: _truncate(event.songArtist, 512),
      albumId: _truncate(event.albumId, 256),
      album: _truncate(event.album, 512),
      albumArtist: _truncate(event.albumArtist, 512),
      songDurationMs: event.songDurationMs,
    );
  }

  static String? _truncate(String? value, int maxLength) {
    if (value == null || value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }

  void _applyToRollup(
    Database db,
    String userId,
    ListeningEvent event,
    int plays,
  ) {
    db.execute('''
      INSERT INTO listening_song_rollups (
        user_id, song_id, play_count, listened_ms, first_played, last_played,
        song_title, song_artist, album_id, album, album_artist
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (user_id, song_id) DO UPDATE SET
        play_count = play_count + excluded.play_count,
        listened_ms = listened_ms + excluded.listened_ms,
        first_played = MIN(COALESCE(first_played, excluded.first_played),
                           excluded.first_played),
        last_played = MAX(COALESCE(last_played, excluded.last_played),
                          excluded.last_played),
        song_title = COALESCE(excluded.song_title, song_title),
        song_artist = COALESCE(excluded.song_artist, song_artist),
        album_id = COALESCE(excluded.album_id, album_id),
        album = COALESCE(excluded.album, album),
        album_artist = COALESCE(excluded.album_artist, album_artist)
    ''', [
      userId,
      event.songId,
      plays,
      event.listenedMs,
      event.occurredAtMs,
      event.occurredAtMs,
      event.songTitle,
      event.songArtist,
      event.albumId,
      event.album,
      event.albumArtist,
    ]);
  }

  /// Account-wide summary for [userId], one rollup per song.
  ListeningStatsSummary getSummary(String userId) {
    final rows = _db.select('''
      SELECT song_id, play_count, listened_ms, first_played, last_played,
             song_title, song_artist, album_id, album, album_artist
      FROM listening_song_rollups
      WHERE user_id = ?
      ORDER BY listened_ms DESC
    ''', [userId]);

    final songs = <ListeningSongRollup>[];
    var totalListenedMs = 0;
    var totalPlays = 0;
    for (final row in rows) {
      final rollup = ListeningSongRollup(
        songId: row['song_id'] as String,
        playCount: row['play_count'] as int? ?? 0,
        listenedMs: row['listened_ms'] as int? ?? 0,
        firstPlayedMs: row['first_played'] as int?,
        lastPlayedMs: row['last_played'] as int?,
        songTitle: row['song_title'] as String?,
        songArtist: row['song_artist'] as String?,
        albumId: row['album_id'] as String?,
        album: row['album'] as String?,
        albumArtist: row['album_artist'] as String?,
      );
      songs.add(rollup);
      totalListenedMs += rollup.listenedMs;
      totalPlays += rollup.playCount;
    }

    return ListeningStatsSummary(
      songs: songs,
      totalListenedMs: totalListenedMs,
      totalPlays: totalPlays,
      generatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  /// Listened milliseconds per local day (`yyyy-mm-dd`) over the last [days]
  /// days, grouped by the listener's local day at the time of each event.
  Map<String, int> getDailyListenedMs(String userId, {int days = 120}) {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days + 1))
        .millisecondsSinceEpoch;
    final rows = _db.select('''
      SELECT
        DATE((occurred_at / 1000) + (tz_offset_min * 60), 'unixepoch') AS day,
        SUM(listened_ms) AS ms
      FROM listening_events
      WHERE user_id = ? AND occurred_at >= ?
        AND event_id NOT LIKE 'baseline:%'
      GROUP BY day
      ORDER BY day ASC
    ''', [userId, cutoff]);

    final result = <String, int>{};
    for (final row in rows) {
      final day = row['day'] as String?;
      if (day == null) continue;
      result[day] = (row['ms'] as int?) ?? 0;
    }
    return result;
  }

  /// Per-song listening totals within the trailing [days] window, newest
  /// activity first. Used for "this week" style views (top artist of the
  /// week, tracks played recently) across all of the user's devices.
  /// Baseline imports are excluded: they compress years of history into one
  /// timestamp and would otherwise dominate the window they landed in.
  List<ListeningSongRollup> getRecentSongTotals(
    String userId, {
    int days = 7,
  }) {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final rows = _db.select('''
      SELECT
        song_id,
        SUM(plays) AS play_count,
        SUM(listened_ms) AS listened_ms,
        MIN(occurred_at) AS first_played,
        MAX(occurred_at) AS last_played,
        MAX(song_title) AS song_title,
        MAX(song_artist) AS song_artist,
        MAX(album_id) AS album_id,
        MAX(album) AS album,
        MAX(album_artist) AS album_artist
      FROM listening_events
      WHERE user_id = ? AND occurred_at >= ?
        AND event_id NOT LIKE 'baseline:%'
      GROUP BY song_id
      ORDER BY last_played DESC
    ''', [userId, cutoff]);

    return rows
        .map((row) => ListeningSongRollup(
              songId: row['song_id'] as String,
              playCount: row['play_count'] as int? ?? 0,
              listenedMs: row['listened_ms'] as int? ?? 0,
              firstPlayedMs: row['first_played'] as int?,
              lastPlayedMs: row['last_played'] as int?,
              songTitle: row['song_title'] as String?,
              songArtist: row['song_artist'] as String?,
              albumId: row['album_id'] as String?,
              album: row['album'] as String?,
              albumArtist: row['album_artist'] as String?,
            ))
        .toList();
  }

  /// Deletes all listening data for [userId] (events and rollups).
  void resetUser(String userId) {
    final db = _db;
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        'DELETE FROM listening_events WHERE user_id = ?',
        [userId],
      );
      db.execute(
        'DELETE FROM listening_song_rollups WHERE user_id = ?',
        [userId],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Recomputes [userId]'s song rollups from the raw event log. The event log
  /// is the source of truth; this exists so rollup bugs are always repairable.
  void rebuildRollups(String userId) {
    final db = _db;
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        'DELETE FROM listening_song_rollups WHERE user_id = ?',
        [userId],
      );
      db.execute('''
        INSERT INTO listening_song_rollups (
          user_id, song_id, play_count, listened_ms, first_played, last_played,
          song_title, song_artist, album_id, album, album_artist
        )
        SELECT
          user_id,
          song_id,
          SUM(plays),
          SUM(listened_ms),
          MIN(occurred_at),
          MAX(occurred_at),
          MAX(song_title),
          MAX(song_artist),
          MAX(album_id),
          MAX(album),
          MAX(album_artist)
        FROM listening_events
        WHERE user_id = ?
        GROUP BY user_id, song_id
      ''', [userId]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() {
    _database?.close();
    _database = null;
  }
}

enum _BaselineOutcome { accepted, duplicate, rejected }
