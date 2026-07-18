part of '../listening_stats_store.dart';

extension _ListeningStatsEventIngestion on ListeningStatsStore {
  ({int accepted, int duplicates, int rejected}) _applyEvents(
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
        for (final raw in events.take(ListeningStatsStore.maxEventsPerBatch)) {
          final event = _sanitize(raw);
          if (event == null) {
            rejected++;
            continue;
          }

          // Baseline events describe a device's imported historical state and
          // may legitimately change. They replace rather than accumulate.
          if (event.eventId.startsWith('baseline:')) {
            final baseline = _applyBaselineEvent(
              db,
              userId,
              deviceId,
              event,
              receivedAt: receivedAt,
            );
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

          // A play whose play-action already counted is stored with its plays
          // zeroed so the event log itself stays double-count-free.
          var plays = event.plays;
          if (plays > 0 && event.playId != null) {
            final rows = findPlay.select([userId, event.playId]);
            if (rows.isNotEmpty) plays = 0;
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

          _applyToSongRollup(db, userId, event, plays);
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
      _applyToSongRollup(db, userId, event, event.plays);
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
    _recomputeSongRollup(db, userId, event.songId);
    // Artist/album/daily rollups can't be patched incrementally after a
    // replacement; the caller schedules a per-user derived rebuild.
    return (outcome: _BaselineOutcome.accepted, replacedExisting: true);
  }

  /// Validates bounds and normalizes an incoming event.
  ListeningEvent? _sanitize(ListeningEvent event) {
    if (event.eventId.isEmpty || event.eventId.length > 128) return null;
    if (event.songId.isEmpty || event.songId.length > 256) return null;
    if (event.listenedMs < 0 || event.plays < 0) return null;

    final isBaseline = event.eventId.startsWith('baseline:');
    final maxListened = isBaseline
        ? ListeningStatsStore.maxListenedMsPerBaselineEvent
        : ListeningStatsStore.maxListenedMsPerEvent;
    final maxPlays =
        isBaseline ? ListeningStatsStore.maxPlaysPerBaselineEvent : 1;
    var listenedMs = event.listenedMs;
    var plays = event.plays;
    if (listenedMs > maxListened) listenedMs = maxListened;
    if (plays > maxPlays) plays = maxPlays;
    if (listenedMs == 0 && plays == 0) return null;

    // Clamp client clocks more than a day in the future to server time.
    var occurredAt = event.occurredAtMs;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (occurredAt > now + Duration.millisecondsPerDay || occurredAt <= 0) {
      occurredAt = now;
    }

    var tzOffset = event.tzOffsetMinutes;
    if (tzOffset < -14 * 60 || tzOffset > 14 * 60) tzOffset = 0;

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
      songTitle: _truncateStatsValue(event.songTitle, 512),
      songArtist: _truncateStatsValue(event.songArtist, 512),
      albumId: _truncateStatsValue(event.albumId, 256),
      album: _truncateStatsValue(event.album, 512),
      albumArtist: _truncateStatsValue(event.albumArtist, 512),
      songDurationMs: event.songDurationMs,
      sourceKind: _normalizePlaybackContext(event.sourceKind, 32),
      playlistId: _normalizePlaybackContext(event.playlistId, 256),
      clientKind: _normalizePlaybackContext(event.clientKind, 32),
    );
  }
}

String? _truncateStatsValue(String? value, int maxLength) {
  if (value == null || value.length <= maxLength) return value;
  return value.substring(0, maxLength);
}

String? _normalizePlaybackContext(String? value, int maxLength) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return _truncateStatsValue(trimmed, maxLength);
}

enum _BaselineOutcome { accepted, duplicate, rejected }
