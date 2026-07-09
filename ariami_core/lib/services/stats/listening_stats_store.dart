import 'dart:io';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/credited_artist_splitter.dart';
import 'package:sqlite3/sqlite3.dart';

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
      _migrateEventColumns(db);
      _backfillDerivedIfNeeded(db);
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
        album_artist TEXT,
        source_kind TEXT,
        playlist_id TEXT,
        client_kind TEXT
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
    // ── Derived tables (rollup schema v2). All of these are disposable:
    // they are rebuilt from listening_events, never the other way around.
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_stats_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    // Current credited-artist list per (user, song), derived server-side from
    // the raw display artist string. The display string on events/rollups is
    // never modified; this table only adds the split view.
    db.execute('''
      CREATE TABLE IF NOT EXISTS song_artist_credits (
        user_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        artist_key TEXT NOT NULL,
        artist_display TEXT NOT NULL,
        ordinal INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (user_id, song_id, artist_key)
      )
    ''');
    // Every credited artist receives the FULL play and FULL listened time of
    // an event — credit is never divided between collaborators.
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_artist_rollups (
        user_id TEXT NOT NULL,
        artist_key TEXT NOT NULL,
        artist_display TEXT,
        play_count INTEGER NOT NULL DEFAULT 0,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        first_played INTEGER,
        last_played INTEGER,
        PRIMARY KEY (user_id, artist_key)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_album_rollups (
        user_id TEXT NOT NULL,
        album_key TEXT NOT NULL,
        album TEXT,
        album_artist TEXT,
        play_count INTEGER NOT NULL DEFAULT 0,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        first_played INTEGER,
        last_played INTEGER,
        PRIMARY KEY (user_id, album_key)
      )
    ''');
    // Generic local-day grain: any period view (day, week, month, year) is a
    // range query over these rows — months/years never need their own tables.
    // Baseline imports are excluded (they compress history into one moment).
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_daily_rollups (
        user_id TEXT NOT NULL,
        local_day TEXT NOT NULL,
        dim TEXT NOT NULL,
        dim_key TEXT NOT NULL,
        play_count INTEGER NOT NULL DEFAULT 0,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        display TEXT,
        display_extra TEXT,
        PRIMARY KEY (user_id, local_day, dim, dim_key)
      )
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_daily_user_dim_day
        ON listening_daily_rollups (user_id, dim, local_day)
    ''');
  }

  /// Adds the optional playback-context columns to a `listening_events` table
  /// created before they existed. Purely additive: old rows keep NULLs and no
  /// data is touched. Idempotent via a `PRAGMA table_info` check.
  void _migrateEventColumns(Database db) {
    final existing = db
        .select('PRAGMA table_info(listening_events)')
        .map((row) => row['name'] as String)
        .toSet();
    const contextColumns = ['source_kind', 'playlist_id', 'client_kind'];
    for (final column in contextColumns) {
      if (!existing.contains(column)) {
        db.execute('ALTER TABLE listening_events ADD COLUMN $column TEXT');
      }
    }
  }

  /// Detects a database written before the derived-rollup schema existed (or
  /// with an older rollup schema) and backfills the derived tables by
  /// replaying the raw event log. Idempotent: rebuilding is a delete +
  /// deterministic replay, so running it twice converges to the same rows.
  void _backfillDerivedIfNeeded(Database db) {
    final versionRows = db.select(
      "SELECT value FROM listening_stats_meta WHERE key = 'rollup_schema_version'",
    );
    final storedVersion = versionRows.isEmpty
        ? 0
        : int.tryParse(versionRows.first['value'] as String? ?? '') ?? 0;
    if (storedVersion >= rollupSchemaVersion) return;

    db.execute('BEGIN IMMEDIATE');
    try {
      final users = db.select('SELECT DISTINCT user_id FROM listening_events');
      for (final row in users) {
        _rebuildDerivedForUser(db, row['user_id'] as String);
      }
      db.execute('''
        INSERT INTO listening_stats_meta (key, value)
        VALUES ('rollup_schema_version', ?)
        ON CONFLICT (key) DO UPDATE SET value = excluded.value
      ''', ['$rollupSchemaVersion']);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
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
    // A replaced baseline changes history non-additively; the derived tables
    // are rebuilt from the log once per batch instead of patched in place.
    var derivedRebuildNeeded = false;
    final receivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;

    final db = _db;
    db.execute('BEGIN IMMEDIATE');
    try {
      final insertEvent = db.prepare('''
        INSERT OR IGNORE INTO listening_events (
          event_id, user_id, device_id, song_id, play_id, listened_ms, plays,
          occurred_at, tz_offset_min, received_at,
          song_title, song_artist, album_id, album, album_artist,
          source_kind, playlist_id, client_kind
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            final baseline = _applyBaselineEvent(db, userId, deviceId, event,
                receivedAt: receivedAt);
            switch (baseline.outcome) {
              case _BaselineOutcome.accepted:
                accepted++;
              case _BaselineOutcome.duplicate:
                duplicates++;
              case _BaselineOutcome.rejected:
                rejected++;
            }
            if (baseline.replacedExisting) derivedRebuildNeeded = true;
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
            event.sourceKind,
            event.playlistId,
            event.clientKind,
          ]);

          if (db.updatedRows == 0) {
            duplicates++;
            continue;
          }

          _applyToRollup(db, userId, event, plays);
          _applyEventToDerived(db, userId, event, plays, isBaseline: false);
          accepted++;
        }
      } finally {
        insertEvent.close();
        findPlay.close();
      }
      if (derivedRebuildNeeded) {
        _rebuildDerivedForUser(db, userId);
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
  ({_BaselineOutcome outcome, bool replacedExisting}) _applyBaselineEvent(
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
      _applyEventToDerived(db, userId, event, event.plays, isBaseline: true);
      return (outcome: _BaselineOutcome.accepted, replacedExisting: false);
    }

    final row = existing.first;
    if (row['user_id'] != userId ||
        row['device_id'] != deviceId ||
        row['song_id'] != event.songId) {
      return (outcome: _BaselineOutcome.rejected, replacedExisting: false);
    }
    if (row['listened_ms'] == event.listenedMs && row['plays'] == event.plays) {
      return (outcome: _BaselineOutcome.duplicate, replacedExisting: false);
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
    // Artist/album/daily rollups can't be patched incrementally after a
    // replacement; the caller schedules a per-user derived rebuild.
    return (outcome: _BaselineOutcome.accepted, replacedExisting: true);
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
      sourceKind: _normalizeContext(event.sourceKind, 32),
      playlistId: _normalizeContext(event.playlistId, 256),
      clientKind: _normalizeContext(event.clientKind, 32),
    );
  }

  static String? _truncate(String? value, int maxLength) {
    if (value == null || value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }

  /// Optional playback-context strings: trimmed, bounded, empty becomes null.
  static String? _normalizeContext(String? value, int maxLength) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return _truncate(trimmed, maxLength);
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

  /// Applies one event to the derived tables (credits, artist/album rollups,
  /// daily rollups). Called with the same sanitized event and effective
  /// [plays] the raw log stores, so an incremental application and a replay
  /// of the log produce identical derived rows.
  void _applyEventToDerived(
    Database db,
    String userId,
    ListeningEvent event,
    int plays, {
    required bool isBaseline,
  }) {
    final rawArtist = event.songArtist ?? event.albumArtist;
    final credits = _splitter.split(rawArtist);
    if (credits.isNotEmpty) {
      _syncSongCredits(db, userId, event.songId, credits);
    }

    for (final credit in credits) {
      db.execute('''
        INSERT INTO listening_artist_rollups (
          user_id, artist_key, artist_display, play_count, listened_ms,
          first_played, last_played
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (user_id, artist_key) DO UPDATE SET
          play_count = play_count + excluded.play_count,
          listened_ms = listened_ms + excluded.listened_ms,
          first_played = MIN(COALESCE(first_played, excluded.first_played),
                             excluded.first_played),
          last_played = MAX(COALESCE(last_played, excluded.last_played),
                            excluded.last_played),
          artist_display = COALESCE(excluded.artist_display, artist_display)
      ''', [
        userId,
        credit.key,
        credit.display,
        plays,
        event.listenedMs,
        event.occurredAtMs,
        event.occurredAtMs,
      ]);
    }

    final albumKey = _albumKeyFor(event.albumId, event.album);
    if (albumKey != null) {
      db.execute('''
        INSERT INTO listening_album_rollups (
          user_id, album_key, album, album_artist, play_count, listened_ms,
          first_played, last_played
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (user_id, album_key) DO UPDATE SET
          play_count = play_count + excluded.play_count,
          listened_ms = listened_ms + excluded.listened_ms,
          first_played = MIN(COALESCE(first_played, excluded.first_played),
                             excluded.first_played),
          last_played = MAX(COALESCE(last_played, excluded.last_played),
                            excluded.last_played),
          album = COALESCE(excluded.album, album),
          album_artist = COALESCE(excluded.album_artist, album_artist)
      ''', [
        userId,
        albumKey,
        event.album,
        event.albumArtist,
        plays,
        event.listenedMs,
        event.occurredAtMs,
        event.occurredAtMs,
      ]);
    }

    // Baseline imports compress a device's whole history into one timestamp;
    // they contribute to all-time rollups above but never to the day grain.
    if (isBaseline) return;

    final localDay = _localDayFor(event.occurredAtMs, event.tzOffsetMinutes);
    _upsertDaily(db, userId, localDay, dimTotal, '', plays, event.listenedMs,
        null, null);
    _upsertDaily(db, userId, localDay, dimSong, event.songId, plays,
        event.listenedMs, event.songTitle, rawArtist);
    for (final credit in credits) {
      _upsertDaily(db, userId, localDay, dimArtist, credit.key, plays,
          event.listenedMs, credit.display, null);
    }
    if (albumKey != null) {
      _upsertDaily(db, userId, localDay, dimAlbum, albumKey, plays,
          event.listenedMs, event.album, event.albumArtist);
    }
  }

  void _upsertDaily(
    Database db,
    String userId,
    String localDay,
    String dim,
    String dimKey,
    int plays,
    int listenedMs,
    String? display,
    String? displayExtra,
  ) {
    db.execute('''
      INSERT INTO listening_daily_rollups (
        user_id, local_day, dim, dim_key, play_count, listened_ms,
        display, display_extra
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (user_id, local_day, dim, dim_key) DO UPDATE SET
        play_count = play_count + excluded.play_count,
        listened_ms = listened_ms + excluded.listened_ms,
        display = COALESCE(excluded.display, display),
        display_extra = COALESCE(excluded.display_extra, display_extra)
    ''', [
      userId,
      localDay,
      dim,
      dimKey,
      plays,
      listenedMs,
      display,
      displayExtra,
    ]);
  }

  /// Keeps the (user, song) credit list matching the latest artist string.
  void _syncSongCredits(
    Database db,
    String userId,
    String songId,
    List<CreditedArtist> credits,
  ) {
    final existing = db.select('''
      SELECT artist_key, artist_display, ordinal FROM song_artist_credits
      WHERE user_id = ? AND song_id = ?
      ORDER BY ordinal
    ''', [userId, songId]);
    if (existing.length == credits.length) {
      var unchanged = true;
      for (var i = 0; i < credits.length; i++) {
        final row = existing[i];
        if (row['artist_key'] != credits[i].key ||
            row['artist_display'] != credits[i].display ||
            row['ordinal'] != credits[i].ordinal) {
          unchanged = false;
          break;
        }
      }
      if (unchanged) return;
    }
    db.execute(
      'DELETE FROM song_artist_credits WHERE user_id = ? AND song_id = ?',
      [userId, songId],
    );
    for (final credit in credits) {
      db.execute('''
        INSERT INTO song_artist_credits (
          user_id, song_id, artist_key, artist_display, ordinal
        ) VALUES (?, ?, ?, ?, ?)
      ''', [userId, songId, credit.key, credit.display, credit.ordinal]);
    }
  }

  /// Rebuilds every derived table (credits, artist/album/daily rollups) for
  /// [userId] by replaying the raw event log in arrival order. Deterministic:
  /// the log already stores effective plays (retried plays are zeroed) and
  /// replaced baselines in their final state. Must run inside a transaction.
  void _rebuildDerivedForUser(Database db, String userId) {
    db.execute(
      'DELETE FROM song_artist_credits WHERE user_id = ?',
      [userId],
    );
    db.execute(
      'DELETE FROM listening_artist_rollups WHERE user_id = ?',
      [userId],
    );
    db.execute(
      'DELETE FROM listening_album_rollups WHERE user_id = ?',
      [userId],
    );
    db.execute(
      'DELETE FROM listening_daily_rollups WHERE user_id = ?',
      [userId],
    );

    final rows = db.select('''
      SELECT event_id, song_id, play_id, listened_ms, plays, occurred_at,
             tz_offset_min, song_title, song_artist, album_id, album,
             album_artist
      FROM listening_events
      WHERE user_id = ?
      ORDER BY rowid
    ''', [userId]);
    for (final row in rows) {
      final eventId = row['event_id'] as String;
      final event = ListeningEvent(
        eventId: eventId,
        songId: row['song_id'] as String,
        playId: row['play_id'] as String?,
        listenedMs: row['listened_ms'] as int? ?? 0,
        plays: row['plays'] as int? ?? 0,
        occurredAtMs: row['occurred_at'] as int,
        tzOffsetMinutes: row['tz_offset_min'] as int? ?? 0,
        songTitle: row['song_title'] as String?,
        songArtist: row['song_artist'] as String?,
        albumId: row['album_id'] as String?,
        album: row['album'] as String?,
        albumArtist: row['album_artist'] as String?,
      );
      _applyEventToDerived(db, userId, event, event.plays,
          isBaseline: eventId.startsWith('baseline:'));
    }
  }

  /// Album grouping key: the album id when known, otherwise a normalized-name
  /// key so untagged libraries still group. Returns null when the event has
  /// no album information at all.
  static String? _albumKeyFor(String? albumId, String? album) {
    if (albumId != null && albumId.isNotEmpty) return albumId;
    if (album != null) {
      final key = normalizeArtistKey(album);
      if (key.isNotEmpty) return 'name:$key';
    }
    return null;
  }

  /// `yyyy-mm-dd` in the listener's local timezone at the time of the event.
  /// Matches the SQL expression the daily-minutes query uses
  /// (`DATE(occurred_at/1000 + tz_offset_min*60, 'unixepoch')`).
  static String _localDayFor(int occurredAtMs, int tzOffsetMinutes) {
    final local = DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true)
        .add(Duration(minutes: tzOffsetMinutes));
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-$month-$day';
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

  /// Aggregated stats for an inclusive local-day range. A single day is
  /// `fromDay == toDay`; months and years are just wider ranges — all served
  /// from the same daily rollup rows. Baseline imports never appear here.
  ListeningPeriodStats getPeriodStats(
    String userId, {
    required String fromDay,
    required String toDay,
    int limit = 50,
  }) {
    final db = _db;

    final days = <String, ListeningDailyTotal>{};
    var totalPlays = 0;
    var totalListenedMs = 0;
    final totalRows = db.select('''
      SELECT local_day, play_count, listened_ms
      FROM listening_daily_rollups
      WHERE user_id = ? AND dim = ? AND local_day BETWEEN ? AND ?
      ORDER BY local_day ASC
    ''', [userId, dimTotal, fromDay, toDay]);
    for (final row in totalRows) {
      final plays = row['play_count'] as int? ?? 0;
      final listenedMs = row['listened_ms'] as int? ?? 0;
      days[row['local_day'] as String] =
          ListeningDailyTotal(playCount: plays, listenedMs: listenedMs);
      totalPlays += plays;
      totalListenedMs += listenedMs;
    }

    ResultSet topRows(String dim) => db.select('''
          SELECT dim_key,
                 SUM(play_count) AS play_count,
                 SUM(listened_ms) AS listened_ms,
                 MAX(display) AS display,
                 MAX(display_extra) AS display_extra
          FROM listening_daily_rollups
          WHERE user_id = ? AND dim = ? AND local_day BETWEEN ? AND ?
          GROUP BY dim_key
          ORDER BY listened_ms DESC
          LIMIT ?
        ''', [userId, dim, fromDay, toDay, limit]);

    final songs = topRows(dimSong)
        .map((row) => ListeningSongRollup(
              songId: row['dim_key'] as String,
              playCount: row['play_count'] as int? ?? 0,
              listenedMs: row['listened_ms'] as int? ?? 0,
              songTitle: row['display'] as String?,
              songArtist: row['display_extra'] as String?,
            ))
        .toList();
    final artists = topRows(dimArtist)
        .map((row) => ListeningArtistRollup(
              artistKey: row['dim_key'] as String,
              artistDisplay: row['display'] as String?,
              playCount: row['play_count'] as int? ?? 0,
              listenedMs: row['listened_ms'] as int? ?? 0,
            ))
        .toList();
    final albums = topRows(dimAlbum)
        .map((row) => _albumRollupFromRow(
              row['dim_key'] as String,
              album: row['display'] as String?,
              albumArtist: row['display_extra'] as String?,
              playCount: row['play_count'] as int? ?? 0,
              listenedMs: row['listened_ms'] as int? ?? 0,
            ))
        .toList();

    return ListeningPeriodStats(
      fromDay: fromDay,
      toDay: toDay,
      totalPlays: totalPlays,
      totalListenedMs: totalListenedMs,
      songs: songs,
      artists: artists,
      albums: albums,
      days: days,
    );
  }

  /// Top credited artists: all-time when [days] is null, otherwise a trailing
  /// window of that many local days (today inclusive) from the daily grain.
  List<ListeningArtistRollup> getTopArtists(
    String userId, {
    int? days,
    int limit = 100,
  }) {
    final db = _db;
    if (days == null) {
      final rows = db.select('''
        SELECT artist_key, artist_display, play_count, listened_ms,
               first_played, last_played
        FROM listening_artist_rollups
        WHERE user_id = ?
        ORDER BY listened_ms DESC
        LIMIT ?
      ''', [userId, limit]);
      return rows
          .map((row) => ListeningArtistRollup(
                artistKey: row['artist_key'] as String,
                artistDisplay: row['artist_display'] as String?,
                playCount: row['play_count'] as int? ?? 0,
                listenedMs: row['listened_ms'] as int? ?? 0,
                firstPlayedMs: row['first_played'] as int?,
                lastPlayedMs: row['last_played'] as int?,
              ))
          .toList();
    }

    final rows = db.select('''
      SELECT dim_key,
             SUM(play_count) AS play_count,
             SUM(listened_ms) AS listened_ms,
             MAX(display) AS display
      FROM listening_daily_rollups
      WHERE user_id = ? AND dim = ? AND local_day >= ?
      GROUP BY dim_key
      ORDER BY listened_ms DESC
      LIMIT ?
    ''', [userId, dimArtist, _trailingWindowStartDay(days), limit]);
    return rows
        .map((row) => ListeningArtistRollup(
              artistKey: row['dim_key'] as String,
              artistDisplay: row['display'] as String?,
              playCount: row['play_count'] as int? ?? 0,
              listenedMs: row['listened_ms'] as int? ?? 0,
            ))
        .toList();
  }

  /// Top albums: all-time when [days] is null, otherwise a trailing window of
  /// that many local days (today inclusive) from the daily grain.
  List<ListeningAlbumRollup> getTopAlbums(
    String userId, {
    int? days,
    int limit = 100,
  }) {
    final db = _db;
    if (days == null) {
      final rows = db.select('''
        SELECT album_key, album, album_artist, play_count, listened_ms,
               first_played, last_played
        FROM listening_album_rollups
        WHERE user_id = ?
        ORDER BY listened_ms DESC
        LIMIT ?
      ''', [userId, limit]);
      return rows
          .map((row) => _albumRollupFromRow(
                row['album_key'] as String,
                album: row['album'] as String?,
                albumArtist: row['album_artist'] as String?,
                playCount: row['play_count'] as int? ?? 0,
                listenedMs: row['listened_ms'] as int? ?? 0,
                firstPlayedMs: row['first_played'] as int?,
                lastPlayedMs: row['last_played'] as int?,
              ))
          .toList();
    }

    final rows = db.select('''
      SELECT dim_key,
             SUM(play_count) AS play_count,
             SUM(listened_ms) AS listened_ms,
             MAX(display) AS display,
             MAX(display_extra) AS display_extra
      FROM listening_daily_rollups
      WHERE user_id = ? AND dim = ? AND local_day >= ?
      GROUP BY dim_key
      ORDER BY listened_ms DESC
      LIMIT ?
    ''', [userId, dimAlbum, _trailingWindowStartDay(days), limit]);
    return rows
        .map((row) => _albumRollupFromRow(
              row['dim_key'] as String,
              album: row['display'] as String?,
              albumArtist: row['display_extra'] as String?,
              playCount: row['play_count'] as int? ?? 0,
              listenedMs: row['listened_ms'] as int? ?? 0,
            ))
        .toList();
  }

  /// Per-local-day plays + listened time over the trailing [days] window,
  /// baseline-free. The listened-ms values match [getDailyListenedMs].
  Map<String, ListeningDailyTotal> getDailyTotals(
    String userId, {
    int days = 120,
  }) {
    final rows = _db.select('''
      SELECT local_day, play_count, listened_ms
      FROM listening_daily_rollups
      WHERE user_id = ? AND dim = ? AND local_day >= ?
      ORDER BY local_day ASC
    ''', [userId, dimTotal, _trailingWindowStartDay(days)]);
    final result = <String, ListeningDailyTotal>{};
    for (final row in rows) {
      result[row['local_day'] as String] = ListeningDailyTotal(
        playCount: row['play_count'] as int? ?? 0,
        listenedMs: row['listened_ms'] as int? ?? 0,
      );
    }
    return result;
  }

  static ListeningAlbumRollup _albumRollupFromRow(
    String albumKey, {
    String? album,
    String? albumArtist,
    required int playCount,
    required int listenedMs,
    int? firstPlayedMs,
    int? lastPlayedMs,
  }) {
    return ListeningAlbumRollup(
      albumKey: albumKey,
      albumId: albumKey.startsWith('name:') ? null : albumKey,
      album: album,
      albumArtist: albumArtist,
      playCount: playCount,
      listenedMs: listenedMs,
      firstPlayedMs: firstPlayedMs,
      lastPlayedMs: lastPlayedMs,
    );
  }

  /// First local day of a trailing [days]-day window ending today (server
  /// UTC), so `days: 7` covers today plus the six previous days.
  static String _trailingWindowStartDay(int days) {
    final start =
        DateTime.now().toUtc().subtract(Duration(days: days > 0 ? days - 1 : 0));
    return _localDayFor(start.millisecondsSinceEpoch, 0);
  }

  /// Deletes all listening data for [userId] (events and every derived
  /// table).
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
      db.execute(
        'DELETE FROM song_artist_credits WHERE user_id = ?',
        [userId],
      );
      db.execute(
        'DELETE FROM listening_artist_rollups WHERE user_id = ?',
        [userId],
      );
      db.execute(
        'DELETE FROM listening_album_rollups WHERE user_id = ?',
        [userId],
      );
      db.execute(
        'DELETE FROM listening_daily_rollups WHERE user_id = ?',
        [userId],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Recomputes all of [userId]'s rollups (song, credited artist, album,
  /// daily) from the raw event log. The event log is the source of truth;
  /// this exists so rollup bugs are always repairable.
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
      _rebuildDerivedForUser(db, userId);
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
