part of '../listening_stats_store.dart';

extension _ListeningStatsRollupMaintenance on ListeningStatsStore {
  void _applyToSongRollup(
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

  /// Recomputes one (user, song) rollup row from the raw event log.
  void _recomputeSongRollup(Database db, String userId, String songId) {
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

  /// Applies one event to credits, artist/album rollups, and daily rollups.
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

    final albumKey = statsAlbumKey(event.albumId, event.album);
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

    // Baseline imports compress a device's history into one timestamp, so
    // they contribute to all-time rollups but never to the day grain.
    if (isBaseline) return;

    final localDay = statsLocalDay(event.occurredAtMs, event.tzOffsetMinutes);
    _upsertDaily(
      db,
      userId,
      localDay,
      ListeningStatsStore.dimTotal,
      '',
      plays,
      event.listenedMs,
      null,
      null,
    );
    _upsertDaily(
      db,
      userId,
      localDay,
      ListeningStatsStore.dimSong,
      event.songId,
      plays,
      event.listenedMs,
      event.songTitle,
      rawArtist,
    );
    for (final credit in credits) {
      _upsertDaily(
        db,
        userId,
        localDay,
        ListeningStatsStore.dimArtist,
        credit.key,
        plays,
        event.listenedMs,
        credit.display,
        null,
      );
    }
    if (albumKey != null) {
      _upsertDaily(
        db,
        userId,
        localDay,
        ListeningStatsStore.dimAlbum,
        albumKey,
        plays,
        event.listenedMs,
        event.album,
        event.albumArtist,
      );
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

  /// Rebuilds every derived table for [userId] from the raw event log.
  void _rebuildDerivedForUser(Database db, String userId) {
    db.execute('DELETE FROM song_artist_credits WHERE user_id = ?', [userId]);
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
      _applyEventToDerived(
        db,
        userId,
        event,
        event.plays,
        isBaseline: eventId.startsWith('baseline:'),
      );
    }
  }

  void _resetUser(String userId) {
    final db = _db;
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute('DELETE FROM listening_events WHERE user_id = ?', [userId]);
      db.execute(
        'DELETE FROM listening_song_rollups WHERE user_id = ?',
        [userId],
      );
      db.execute('DELETE FROM song_artist_credits WHERE user_id = ?', [userId]);
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

  void _rebuildRollups(String userId) {
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
}


