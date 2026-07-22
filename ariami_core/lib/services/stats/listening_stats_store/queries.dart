part of '../listening_stats_store.dart';

extension _ListeningStatsQueries on ListeningStatsStore {
  ListeningStatsSummary _getSummary(String userId) {
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

    // Derived from the raw event log, not rollups: a single index seek on
    // idx_listening_events_user_event thanks to the LIMIT 1 existence probe.
    // The GLOB pattern is a hardcoded literal, never user-controlled.
    final hasSpotifyImport = _db.select(
      'SELECT 1 FROM listening_events '
      "WHERE user_id = ? AND event_id GLOB 'spotify:*' LIMIT 1",
      [userId],
    ).isNotEmpty;

    return ListeningStatsSummary(
      songs: songs,
      totalListenedMs: totalListenedMs,
      totalPlays: totalPlays,
      generatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      hasSpotifyImport: hasSpotifyImport,
    );
  }

  Map<String, int> _getDailyListenedMs(
    String userId, {
    required int days,
  }) {
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

  List<ListeningSongRollup> _getRecentSongTotals(
    String userId, {
    required int days,
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
        .map(
          (row) => ListeningSongRollup(
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
          ),
        )
        .toList();
  }

  ListeningPeriodStats _getPeriodStats(
    String userId, {
    required String fromDay,
    required String toDay,
    required int limit,
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
    ''', [
      userId,
      ListeningStatsStore.dimTotal,
      fromDay,
      toDay,
    ]);
    for (final row in totalRows) {
      final plays = row['play_count'] as int? ?? 0;
      final listenedMs = row['listened_ms'] as int? ?? 0;
      days[row['local_day'] as String] =
          ListeningDailyTotal(playCount: plays, listenedMs: listenedMs);
      totalPlays += plays;
      totalListenedMs += listenedMs;
    }

    // Time-only events feed period totals, but a ranked entity must have
    // crossed the play threshold at least once in the range.
    final sqlLimit = _statsSqlLimit(limit);
    ResultSet topRows(String dim) => db.select('''
          SELECT dim_key,
                 SUM(play_count) AS play_count,
                 SUM(listened_ms) AS listened_ms,
                 MAX(display) AS display,
                 MAX(display_extra) AS display_extra
          FROM listening_daily_rollups
          WHERE user_id = ? AND dim = ? AND local_day BETWEEN ? AND ?
          GROUP BY dim_key
          HAVING SUM(play_count) > 0
          ORDER BY listened_ms DESC
          LIMIT ?
        ''', [userId, dim, fromDay, toDay, sqlLimit]);

    final songs = topRows(ListeningStatsStore.dimSong)
        .map(
          (row) => ListeningSongRollup(
            songId: row['dim_key'] as String,
            playCount: row['play_count'] as int? ?? 0,
            listenedMs: row['listened_ms'] as int? ?? 0,
            songTitle: row['display'] as String?,
            songArtist: row['display_extra'] as String?,
          ),
        )
        .toList();
    final artists = topRows(ListeningStatsStore.dimArtist)
        .map(
          (row) => ListeningArtistRollup(
            artistKey: row['dim_key'] as String,
            artistDisplay: row['display'] as String?,
            playCount: row['play_count'] as int? ?? 0,
            listenedMs: row['listened_ms'] as int? ?? 0,
          ),
        )
        .toList();
    final albums = topRows(ListeningStatsStore.dimAlbum)
        .map(
          (row) => _statsAlbumRollup(
            row['dim_key'] as String,
            album: row['display'] as String?,
            albumArtist: row['display_extra'] as String?,
            playCount: row['play_count'] as int? ?? 0,
            listenedMs: row['listened_ms'] as int? ?? 0,
          ),
        )
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

  List<ListeningArtistRollup> _getTopArtists(
    String userId, {
    required int? days,
    required int limit,
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
      ''', [userId, _statsSqlLimit(limit)]);
      return rows
          .map(
            (row) => ListeningArtistRollup(
              artistKey: row['artist_key'] as String,
              artistDisplay: row['artist_display'] as String?,
              playCount: row['play_count'] as int? ?? 0,
              listenedMs: row['listened_ms'] as int? ?? 0,
              firstPlayedMs: row['first_played'] as int?,
              lastPlayedMs: row['last_played'] as int?,
            ),
          )
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
    ''', [
      userId,
      ListeningStatsStore.dimArtist,
      _statsTrailingWindowStartDay(days),
      _statsSqlLimit(limit),
    ]);
    return rows
        .map(
          (row) => ListeningArtistRollup(
            artistKey: row['dim_key'] as String,
            artistDisplay: row['display'] as String?,
            playCount: row['play_count'] as int? ?? 0,
            listenedMs: row['listened_ms'] as int? ?? 0,
          ),
        )
        .toList();
  }

  List<ListeningAlbumRollup> _getTopAlbums(
    String userId, {
    required int? days,
    required int limit,
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
      ''', [userId, _statsSqlLimit(limit)]);
      return rows
          .map(
            (row) => _statsAlbumRollup(
              row['album_key'] as String,
              album: row['album'] as String?,
              albumArtist: row['album_artist'] as String?,
              playCount: row['play_count'] as int? ?? 0,
              listenedMs: row['listened_ms'] as int? ?? 0,
              firstPlayedMs: row['first_played'] as int?,
              lastPlayedMs: row['last_played'] as int?,
            ),
          )
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
    ''', [
      userId,
      ListeningStatsStore.dimAlbum,
      _statsTrailingWindowStartDay(days),
      _statsSqlLimit(limit),
    ]);
    return rows
        .map(
          (row) => _statsAlbumRollup(
            row['dim_key'] as String,
            album: row['display'] as String?,
            albumArtist: row['display_extra'] as String?,
            playCount: row['play_count'] as int? ?? 0,
            listenedMs: row['listened_ms'] as int? ?? 0,
          ),
        )
        .toList();
  }

  Map<String, ListeningDailyTotal> _getDailyTotals(
    String userId, {
    required int days,
  }) {
    final rows = _db.select('''
      SELECT local_day, play_count, listened_ms
      FROM listening_daily_rollups
      WHERE user_id = ? AND dim = ? AND local_day >= ?
      ORDER BY local_day ASC
    ''', [
      userId,
      ListeningStatsStore.dimTotal,
      _statsTrailingWindowStartDay(days),
    ]);
    final result = <String, ListeningDailyTotal>{};
    for (final row in rows) {
      result[row['local_day'] as String] = ListeningDailyTotal(
        playCount: row['play_count'] as int? ?? 0,
        listenedMs: row['listened_ms'] as int? ?? 0,
      );
    }
    return result;
  }
}

ListeningAlbumRollup _statsAlbumRollup(
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

/// A non-positive limit means "every row": SQLite treats `LIMIT -1` as
/// unlimited (while `LIMIT 0` would return nothing).
int _statsSqlLimit(int limit) => limit > 0 ? limit : -1;

/// First local day of a trailing [days]-day window ending today (server UTC).
String _statsTrailingWindowStartDay(int days) {
  final start =
      DateTime.now().toUtc().subtract(Duration(days: days > 0 ? days - 1 : 0));
  return statsLocalDay(start.millisecondsSinceEpoch, 0);
}
