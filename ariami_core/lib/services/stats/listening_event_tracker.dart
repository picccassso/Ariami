import 'dart:math';

import 'package:ariami_core/models/listening_stats_models.dart';

/// Static metadata about the track a play-action is credited to.
class ListeningTrackInfo {
  final String songId;
  final String? title;
  final String? artist;
  final String? albumId;
  final String? album;
  final String? albumArtist;
  final int durationMs;

  const ListeningTrackInfo({
    required this.songId,
    this.title,
    this.artist,
    this.albumId,
    this.album,
    this.albumArtist,
    this.durationMs = 0,
  });
}

/// Turns raw playback callbacks into honest [ListeningEvent]s.
///
/// Feed it [onTrackChanged], [onPlayingChanged] and frequent [onPositionTick]
/// calls from the audio engine; it emits:
/// - time-segment events for genuine forward listening (scrub jumps beyond
///   [seekToleranceMs] are ignored, so seeking never inflates time), and
/// - exactly one play event per play-action, once cumulative listening reaches
///   30 seconds or half the track, whichever is smaller.
///
/// Repeat-one is counted honestly: a wrap back to the start of the same track
/// finalizes the current play-action and starts a new one, so each full listen
/// counts as one play while every second is still only credited once.
class ListeningEventTracker {
  ListeningEventTracker({
    required this.onEvent,
    String? idSalt,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        _idSalt = idSalt ?? _randomSalt();

  /// Receives finalized events, ready for the outbox.
  final void Function(ListeningEvent event) onEvent;

  final DateTime Function() _now;
  final String _idSalt;
  static final Random _random = Random();

  /// Position jumps larger than this are treated as seeks, not listening.
  static const int seekToleranceMs = 2000;

  /// Uncommitted listening is checkpointed into an event this often, so a
  /// killed app loses at most this much credit.
  static const int checkpointMs = 30000;

  /// The standard play-count threshold (Spotify-style 30 seconds).
  static const int playThresholdMs = 30000;

  /// Segments shorter than this are noise and never emitted.
  static const int minSegmentMs = 1000;

  /// A backward jump landing below this position is treated as the track
  /// restarting (repeat-one wrap or an intentional restart) — a new
  /// play-action rather than a scrub within the current one.
  static const int restartPositionMs = 5000;

  ListeningTrackInfo? _track;
  String? _playId;
  bool _playing = false;
  bool _playCounted = false;
  int _actionListenedMs = 0; // total credited in the current play-action
  int _uncommittedMs = 0; // credited but not yet emitted as a segment
  int? _lastPositionMs;
  int _idCounter = 0;

  static String _randomSalt() =>
      Random.secure().nextInt(0x7fffffff).toRadixString(36);

  String _newId(String kind) {
    _idCounter++;
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
    final rand = _random.nextInt(0xffffff).toRadixString(36);
    return '$kind-$_idSalt-$ts-$_idCounter-$rand';
  }

  /// The play threshold for the current track: 30s, or half the track when
  /// that is shorter (so short tracks can still count).
  int get _playThresholdForTrack {
    final duration = _track?.durationMs ?? 0;
    if (duration > 0) {
      return min(playThresholdMs, duration ~/ 2);
    }
    return playThresholdMs;
  }

  /// Call when the current track changes (or becomes null when playback
  /// stops). Safe to call redundantly with the same track.
  void onTrackChanged(ListeningTrackInfo? track) {
    if (track?.songId == _track?.songId) {
      // Same track (or still nothing): keep the play-action alive across
      // redundant notifications.
      if (track != null) _track = track; // pick up late-arriving duration
      return;
    }
    _finalizePlayAction();
    _track = track;
    _startPlayAction();
  }

  /// Call whenever the engine flips between advancing audio and being paused,
  /// stalled or stopped.
  void onPlayingChanged(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    if (!playing) {
      // Pausing commits what we have; resuming re-anchors the position so a
      // seek performed while paused can never be credited.
      _emitSegmentIfAny();
      _lastPositionMs = null;
    }
  }

  /// Call on every position tick from the audio engine.
  void onPositionTick(int positionMs) {
    if (_track == null || !_playing) {
      _lastPositionMs = positionMs;
      return;
    }

    final last = _lastPositionMs;
    _lastPositionMs = positionMs;
    if (last == null) return;

    final delta = positionMs - last;
    if (delta < 0) {
      // Backward movement is never credited. A large jump back to the start
      // is the track restarting (repeat-one wrap / manual restart): finalize
      // the current play-action honestly and open a new one.
      if (delta < -seekToleranceMs && positionMs <= restartPositionMs) {
        _finalizePlayAction();
        _startPlayAction();
        _lastPositionMs = positionMs;
      }
      return;
    }
    if (delta > seekToleranceMs) {
      // Forward scrub: skip the jumped-over audio, keep listening after it.
      return;
    }
    if (delta == 0) return;

    // Never credit past the end of the track within one tick.
    var credit = delta;
    final duration = _track!.durationMs;
    if (duration > 0 && positionMs > duration) {
      credit = max(0, duration - last);
      if (credit == 0) return;
    }

    _actionListenedMs += credit;
    _uncommittedMs += credit;

    if (!_playCounted && _actionListenedMs >= _playThresholdForTrack) {
      _playCounted = true;
      _emitPlay();
    }
    if (_uncommittedMs >= checkpointMs) {
      _emitSegmentIfAny();
    }
  }

  /// Explicit seek notification (optional; large position jumps are detected
  /// anyway). Re-anchors so the jump itself is never credited.
  void onSeek() {
    _lastPositionMs = null;
  }

  /// Commits any uncommitted listening as a segment event. Call before the
  /// app suspends or quits so credit isn't lost.
  void flush() {
    _emitSegmentIfAny();
  }

  /// Ends the current play-action (track change, stop). Also flushes.
  void stop() {
    _finalizePlayAction();
    _track = null;
    _playing = false;
  }

  void _startPlayAction() {
    _playId = _track == null ? null : _newId('play');
    _playCounted = false;
    _actionListenedMs = 0;
    _uncommittedMs = 0;
    _lastPositionMs = null;
  }

  void _finalizePlayAction() {
    _emitSegmentIfAny();
    _playId = null;
    _playCounted = false;
    _actionListenedMs = 0;
    _uncommittedMs = 0;
    _lastPositionMs = null;
  }

  void _emitPlay() {
    final track = _track;
    if (track == null) return;
    onEvent(_buildEvent(track, listenedMs: 0, plays: 1));
  }

  void _emitSegmentIfAny() {
    final track = _track;
    if (track == null) return;
    if (_uncommittedMs < minSegmentMs) return;
    final ms = _uncommittedMs;
    _uncommittedMs = 0;
    onEvent(_buildEvent(track, listenedMs: ms, plays: 0));
  }

  ListeningEvent _buildEvent(
    ListeningTrackInfo track, {
    required int listenedMs,
    required int plays,
  }) {
    final now = _now();
    return ListeningEvent(
      eventId: _newId(plays > 0 ? 'p' : 's'),
      songId: track.songId,
      playId: _playId,
      listenedMs: listenedMs,
      plays: plays,
      occurredAtMs: now.toUtc().millisecondsSinceEpoch,
      tzOffsetMinutes: now.timeZoneOffset.inMinutes,
      songTitle: track.title,
      songArtist: track.artist,
      albumId: track.albumId,
      album: track.album,
      albumArtist: track.albumArtist,
      songDurationMs: track.durationMs > 0 ? track.durationMs : null,
    );
  }
}
