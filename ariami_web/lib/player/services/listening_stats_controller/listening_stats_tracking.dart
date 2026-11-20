part of '../listening_stats_controller.dart';

extension _ListeningStatsTracking on ListeningStatsController {
  List<ListeningEvent> _pendingEvents() {
    final outbox = _outbox;
    if (outbox == null || outbox.isEmpty) return const <ListeningEvent>[];
    return outbox.peek(outbox.length);
  }

  Map<String, int> get _pendingDayMs {
    if (!_pendingDaysDirty) return _pendingDayMsCache;
    final result = <String, int>{};
    for (final event in _pendingEvents()) {
      if (event.listenedMs <= 0) continue;
      final local = DateTime.fromMillisecondsSinceEpoch(
        event.occurredAtMs,
        isUtc: true,
      ).add(Duration(minutes: event.tzOffsetMinutes));
      final key = _dateKey(local);
      result[key] = (result[key] ?? 0) + event.listenedMs;
    }
    _pendingDayMsCache = result;
    _pendingDaysDirty = false;
    return result;
  }

  int _displayedSecondsForDay(DateTime day) {
    if (!_hasAccountHighlights) return _secondsForDay(day).round();
    final key = _dateKey(day);
    final ms = (_accountDailyMs[key] ?? 0) + (_pendingDayMs[key] ?? 0);
    return ms ~/ 1000;
  }

  void _onAudioChanged() {
    final audio = _audio;
    if (audio == null) return;
    final now = DateTime.now();
    final playing = audio.isPlaying;

    // Honest per-track events for the account, from this device's own engine
    // only. Mirrored Connect playback is excluded here — the device actually
    // playing the audio reports it, so the account never counts it twice.
    final tracker = _tracker;
    if (tracker != null) {
      final localTrack = audio.localCurrentTrack;
      final context = _sourceContext(audio.localSourceId);
      final album = localTrack?.albumId == null
          ? null
          : _albumCatalog[localTrack!.albumId];
      tracker.onTrackChanged(localTrack == null
          ? null
          : ListeningTrackInfo(
              songId: localTrack.id,
              title: localTrack.title,
              artist: localTrack.artist,
              albumId: localTrack.albumId,
              album: localTrack.albumTitle ?? album?.title,
              albumArtist: localTrack.albumArtist ?? album?.artist,
              durationMs: localTrack.durationSeconds * 1000,
              sourceKind: context.sourceKind,
              playlistId: context.playlistId,
            ));
      tracker.onPlayingChanged(audio.localIsPlaying);
      if (audio.localIsPlaying) {
        tracker.onPositionTick(audio.localPosition.inMilliseconds);
      }
    }

    if (playing) {
      final last = _lastTick;
      if (last != null) {
        final delta = now.difference(last).inMilliseconds / 1000.0;
        if (delta > 0) {
          // Notifications can be sparse (mirrored playback ticks once a
          // second), so cap the credited gap: a stall never counts as
          // listening time.
          _addSeconds(now, delta.clamp(0.0, 5.0));
        }
      }
      _lastTick = now;
    } else {
      _lastTick = null;
    }

    final track = audio.currentTrack;
    if (playing && track != null && track.id != _creditedTrackId) {
      _creditedTrackId = track.id;
      _events.insert(
        0,
        PlayEvent(timestamp: now, artist: track.artist, title: track.title),
      );
      if (_events.length > ListeningStatsController._maxEvents) {
        _events = _events.sublist(0, ListeningStatsController._maxEvents);
      }
      _markDirty();
      _notifyListeners();
    }

    final source = audio.sourceId;
    if (playing && source != null && source != _lastSourceId) {
      _lastSourceId = source;
      _recentSources = <String>[
        source,
        ..._recentSources.where((s) => s != source),
      ].take(ListeningStatsController._maxRecentSources).toList();
      _markDirty();
      _notifyListeners();
    }
  }

  void _addSeconds(DateTime now, double seconds) {
    final key = _dateKey(now);
    _dailySeconds[key] = (_dailySeconds[key] ?? 0) + seconds;
    _markDirty();
    // Only surface a change when a user-visible minute rolls over, so the
    // high-frequency position stream doesn't rebuild the home view every tick.
    final minutes = minutesToday;
    if (minutes != _lastMinutesToday) {
      _lastMinutesToday = minutes;
      _notifyListeners();
    }
  }

  double _secondsForDay(DateTime day) => _dailySeconds[_dateKey(day)] ?? 0;
}

/// Maps the queue's namespaced source key (`album:<id>` / `playlist:<id>`)
/// to the optional event context. Unknown or absent sources carry none.
({String? sourceKind, String? playlistId}) _sourceContext(String? sourceId) {
  if (sourceId == null || sourceId.isEmpty) {
    return (sourceKind: null, playlistId: null);
  }
  if (sourceId.startsWith('album:')) {
    return (sourceKind: 'album', playlistId: null);
  }
  if (sourceId.startsWith('playlist:')) {
    final id = sourceId.substring('playlist:'.length);
    return (sourceKind: 'playlist', playlistId: id.isEmpty ? null : id);
  }
  return (sourceKind: null, playlistId: null);
}

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
