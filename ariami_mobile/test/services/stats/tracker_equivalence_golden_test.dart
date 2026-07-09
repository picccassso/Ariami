import 'dart:io';

import 'package:ariami_core/ariami_core.dart'
    show ListeningEvent, ListeningEventTracker, ListeningTrackInfo;
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/services/stats/streaming_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Golden equivalence tests: the mobile stats pipeline and the shared core
/// [ListeningEventTracker] (in its mobile configuration: 15s checkpoints,
/// trusted forward jumps while playing, session-driven restarts) must emit
/// equivalent [ListeningEvent] streams for the same playback script.
///
/// This is the contract that lets mobile delegate its play/time rules to the
/// core tracker without changing user-visible play-count semantics. Every
/// script uses whole-second ticks; the one deliberate difference between the
/// engines — the core tracker drops sub-second residue segments (<1s) that
/// the old mobile code would emit — is invisible at this granularity and in
/// the local seconds-based stats.
///
/// Playback scripts speak the mobile session vocabulary (start / tick / stop
/// with optional natural completion / explicit seek / active flag) and run
/// against both engines through a tiny harness interface.

Song _song({
  required String id,
  required Duration duration,
  String artist = 'Artist',
}) {
  return Song(
    id: id,
    title: 'Title $id',
    artist: artist,
    duration: duration,
    filePath: '/test/$id.mp3',
    fileSize: 1000,
    modifiedTime: DateTime(2024, 1, 1),
  );
}

/// The mobile playback-session vocabulary both engines are driven through.
abstract class _StatsHarness {
  void start(Song song, {bool isResume = false});
  Future<void> stop({bool completedNaturally = false});
  void tick(int seconds);
  void seek();
  void setActive(bool active);
  List<ListeningEvent> get events;
}

/// Drives the real mobile [StreamingStatsService], capturing what it mirrors
/// to the account pipeline.
class _MobileHarness implements _StatsHarness {
  _MobileHarness(this._service) {
    _service.onListeningEvent = events.add;
  }

  final StreamingStatsService _service;

  @override
  final List<ListeningEvent> events = <ListeningEvent>[];

  @override
  void start(Song song, {bool isResume = false}) =>
      _service.onSongStarted(song, isResume: isResume);

  @override
  Future<void> stop({bool completedNaturally = false}) =>
      _service.onSongStopped(completedNaturally: completedNaturally);

  @override
  void tick(int seconds) =>
      _service.updatePosition(Duration(seconds: seconds));

  @override
  void seek() => _service.markPositionDiscontinuity();

  @override
  void setActive(bool active) => _service.setPlaybackActive(active);
}

/// Drives the core tracker through the exact session adapter mobile will use:
/// - start(isResume: false) ends the previous play-action first, so an
///   explicit restart/repeat gets a fresh playId;
/// - stop(completedNaturally) applies the short-song completion rule, then
///   pauses (committing pending time) while keeping the action resumable.
class _CoreHarness implements _StatsHarness {
  _CoreHarness()
      : events = <ListeningEvent>[] {
    _tracker = ListeningEventTracker(
      onEvent: events.add,
      checkpointMs: 15000,
      trustPlayingForwardJumps: true,
      detectRestarts: false,
      clientKind: 'mobile',
    );
  }

  late final ListeningEventTracker _tracker;

  @override
  final List<ListeningEvent> events;

  @override
  void start(Song song, {bool isResume = false}) {
    if (!isResume) _tracker.stop();
    _tracker.onTrackChanged(ListeningTrackInfo(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      albumId: song.albumId,
      album: song.album,
      albumArtist: song.albumArtist,
      durationMs: song.duration.inMilliseconds,
    ));
    _tracker.onPlayingChanged(true);
  }

  @override
  Future<void> stop({bool completedNaturally = false}) async {
    if (completedNaturally) _tracker.onTrackCompleted();
    _tracker.onPlayingChanged(false);
  }

  @override
  void tick(int seconds) => _tracker.onPositionTick(seconds * 1000);

  @override
  void seek() => _tracker.onSeek();

  @override
  void setActive(bool active) => _tracker.onPlayingChanged(active);
}

/// One song's emitted events, normalized for comparison: the ordered
/// (plays, listenedMs) shapes plus how many distinct play-actions earned a
/// play. EventIds, timestamps and concrete playId values differ by design.
typedef _SongTrace = ({
  List<String> shapes,
  int distinctPlayActions,
});

Map<String, _SongTrace> _normalize(List<ListeningEvent> events) {
  final shapes = <String, List<String>>{};
  final playIds = <String, Set<String>>{};
  for (final event in events) {
    shapes
        .putIfAbsent(event.songId, () => <String>[])
        .add('plays=${event.plays} ms=${event.listenedMs}');
    if (event.plays > 0) {
      playIds
          .putIfAbsent(event.songId, () => <String>{})
          .add(event.playId ?? event.eventId);
    }
  }
  return {
    for (final songId in shapes.keys)
      songId: (
        shapes: shapes[songId]!,
        distinctPlayActions: playIds[songId]?.length ?? 0,
      ),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // Test files run in parallel isolates but share the on-disk sqflite
  // directory; give this file its own so resetAllStats here can never race
  // another stats test's flush/reload cycle.
  final dbDir = Directory.systemTemp.createTempSync('golden_stats_db');
  databaseFactory.setDatabasesPath(dbDir.path);
  tearDownAll(() {
    try {
      dbDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  late StreamingStatsService service;

  setUpAll(() async {
    service = StreamingStatsService();
    await service.initialize();
  });

  setUp(() async {
    await service.resetAllStats();
    service.resetForTests();
  });

  tearDownAll(() {
    service.dispose();
  });

  /// Runs [script] against both engines and asserts the emitted event
  /// streams are equivalent.
  Future<void> expectEquivalent(
    Future<void> Function(_StatsHarness harness) script,
  ) async {
    final mobile = _MobileHarness(service);
    await script(mobile);
    // Let any unawaited finalization inside the service settle.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final core = _CoreHarness();
    await script(core);

    final mobileTrace = _normalize(mobile.events);
    final coreTrace = _normalize(core.events);

    expect(coreTrace.keys.toSet(), mobileTrace.keys.toSet(),
        reason: 'both engines must credit the same songs');
    for (final songId in mobileTrace.keys) {
      expect(coreTrace[songId]!.shapes, mobileTrace[songId]!.shapes,
          reason: 'event shapes for $songId must match');
      expect(
        coreTrace[songId]!.distinctPlayActions,
        mobileTrace[songId]!.distinctPlayActions,
        reason: 'distinct play-actions for $songId must match',
      );
    }
  }

  group('mobile/core tracker golden equivalence', () {
    test('a plain 35s listen earns one play and identical segments', () async {
      final song = _song(id: 'g1', duration: const Duration(minutes: 3));
      await expectEquivalent((harness) async {
        harness.start(song);
        for (var i = 0; i <= 35; i++) {
          harness.tick(i);
        }
        await harness.stop();
      });
    });

    test('stopping before 30s earns time but no play', () async {
      final song = _song(id: 'g2', duration: const Duration(minutes: 3));
      await expectEquivalent((harness) async {
        harness.start(song);
        for (var i = 0; i <= 25; i++) {
          harness.tick(i);
        }
        await harness.stop();
      });
    });

    test('pause/resume keeps one play-action across the threshold', () async {
      final song = _song(id: 'g3', duration: const Duration(minutes: 3));
      await expectEquivalent((harness) async {
        harness.start(song);
        for (var i = 0; i <= 20; i++) {
          harness.tick(i);
        }
        await harness.stop();
        harness.start(song, isResume: true);
        for (var i = 20; i <= 40; i++) {
          harness.tick(i);
        }
        await harness.stop();
      });
    });

    test('explicit seeks are never credited', () async {
      final song = _song(id: 'g4', duration: const Duration(minutes: 3));
      await expectEquivalent((harness) async {
        harness.start(song);
        harness.tick(0);
        for (var i = 1; i <= 5; i++) {
          harness.tick(i);
        }
        harness.seek();
        for (var i = 80; i <= 90; i++) {
          harness.tick(i);
        }
        harness.seek();
        for (var i = 20; i <= 25; i++) {
          harness.tick(i);
        }
        await harness.stop();
      });
    });

    test('scrubbing back and forth cannot inflate plays', () async {
      final song = _song(id: 'g5', duration: const Duration(minutes: 3));
      await expectEquivalent((harness) async {
        harness.start(song);
        for (var i = 0; i <= 35; i++) {
          harness.tick(i);
        }
        // Drag back to the start (notified as a discontinuity) and keep
        // listening: still the same play-action, no second play.
        harness.seek();
        for (var i = 0; i <= 35; i++) {
          harness.tick(i);
        }
        await harness.stop();
      });
    });

    test('a short track counts at 50% of its duration', () async {
      final song = _song(id: 'g6', duration: const Duration(seconds: 20));
      await expectEquivalent((harness) async {
        harness.start(song);
        for (var i = 0; i <= 20; i++) {
          harness.tick(i);
        }
        await harness.stop(completedNaturally: true);
      });
    });

    test(
        'a short track finishing naturally below its threshold still counts '
        'exactly one play', () async {
      final song = _song(id: 'g7', duration: const Duration(seconds: 15));
      await expectEquivalent((harness) async {
        harness.start(song);
        for (var i = 0; i <= 7; i++) {
          harness.tick(i);
        }
        await harness.stop(completedNaturally: true);
      });
    });

    test('repeat-one earns a distinct play-action per loop', () async {
      final song = _song(id: 'g8', duration: const Duration(seconds: 25));
      await expectEquivalent((harness) async {
        harness.start(song);
        for (var i = 0; i <= 25; i++) {
          harness.tick(i);
        }
        await harness.stop(completedNaturally: true);
        harness.start(song); // repeat-one: a fresh session
        for (var i = 0; i <= 25; i++) {
          harness.tick(i);
        }
        await harness.stop(completedNaturally: true);
        harness.start(song); // third loop, abandoned early
        for (var i = 0; i <= 10; i++) {
          harness.tick(i);
        }
        await harness.stop();
      });
    });

    test('coalesced background jumps are credited while playing', () async {
      final song = _song(id: 'g9', duration: const Duration(minutes: 3));
      await expectEquivalent((harness) async {
        harness.start(song);
        harness.tick(0);
        harness.tick(45); // one 45s background jump
        await harness.stop();
      });
    });

    test('jumps while paused are never credited', () async {
      final song = _song(id: 'g10', duration: const Duration(minutes: 3));
      await expectEquivalent((harness) async {
        harness.start(song);
        for (var i = 0; i <= 5; i++) {
          harness.tick(i);
        }
        harness.setActive(false);
        harness.tick(120); // position moved while paused
        harness.setActive(true);
        harness.tick(120);
        for (var i = 121; i <= 126; i++) {
          harness.tick(i);
        }
        await harness.stop();
      });
    });

    test('long listens checkpoint into the same segment cadence', () async {
      final song = _song(id: 'g11', duration: const Duration(minutes: 3));
      await expectEquivalent((harness) async {
        harness.start(song);
        for (var i = 0; i <= 95; i++) {
          harness.tick(i);
        }
        await harness.stop();
      });
    });

    test('switching songs finalizes the first and credits the second',
        () async {
      final songA = _song(id: 'g12a', duration: const Duration(minutes: 3));
      final songB = _song(id: 'g12b', duration: const Duration(minutes: 3));
      await expectEquivalent((harness) async {
        harness.start(songA);
        for (var i = 0; i <= 10; i++) {
          harness.tick(i);
        }
        harness.start(songB);
        for (var i = 0; i <= 35; i++) {
          harness.tick(i);
        }
        await harness.stop();
      });
    });
  });
}
