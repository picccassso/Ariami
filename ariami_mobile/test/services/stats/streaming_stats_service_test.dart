import 'dart:io';

import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/services/stats/streaming_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Song _testSong({
  required String id,
  required String title,
  required Duration duration,
  String artist = 'Test Artist',
}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    duration: duration,
    filePath: '/test/$id.mp3',
    fileSize: 1000,
    modifiedTime: DateTime(2024, 1, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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

  group('StreamingStatsService', () {
    // ------------------------------------------------------------------------
    // Basic play counting
    // ------------------------------------------------------------------------
    test('counts a play after 30s of position-based listening', () async {
      final song = _testSong(
        id: 's1',
        title: 'Song 1',
        duration: const Duration(minutes: 3),
      );

      service.onSongStarted(song);
      for (int i = 0; i <= 31; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();

      final stats = service.getSongStats('s1');
      expect(stats, isNotNull);
      expect(stats!.playCount, 1);
      expect(stats.totalTime.inSeconds, greaterThanOrEqualTo(30));
    });

    test('does not count a play before 30s', () async {
      final song = _testSong(
        id: 's2',
        title: 'Song 2',
        duration: const Duration(minutes: 3),
      );

      service.onSongStarted(song);
      for (int i = 0; i <= 25; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();

      final stats = service.getSongStats('s2');
      expect(stats, isNotNull);
      expect(stats!.playCount, 0);
      expect(stats.totalTime.inSeconds, 25);
    });

    // ------------------------------------------------------------------------
    // Pause / resume behaviour
    // ------------------------------------------------------------------------
    test('does not double-count when pausing and resuming', () async {
      final song = _testSong(
        id: 's3',
        title: 'Song 3',
        duration: const Duration(minutes: 3),
      );

      service.onSongStarted(song);
      for (int i = 0; i <= 35; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      expect(service.getSongStats('s3')!.playCount, 1);

      await service.onSongStopped();
      service.onSongStarted(song, isResume: true);
      for (int i = 35; i <= 40; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();

      expect(service.getSongStats('s3')!.playCount, 1);
    });

    test('counts cumulative time across pause/resume', () async {
      final song = _testSong(
        id: 's4',
        title: 'Song 4',
        duration: const Duration(minutes: 3),
      );

      // First chunk: 20s
      service.onSongStarted(song);
      for (int i = 0; i <= 20; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();

      expect(service.getSongStats('s4')!.totalTime.inSeconds, 20);
      expect(service.getSongStats('s4')!.playCount, 0);

      // Resume and listen another 15s -> crosses 30s threshold
      service.onSongStarted(song, isResume: true);
      for (int i = 20; i <= 35; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();

      final stats = service.getSongStats('s4');
      expect(stats!.playCount, 1);
      expect(stats.totalTime.inSeconds, 35);
    });

    // ------------------------------------------------------------------------
    // Short-song rule
    // ------------------------------------------------------------------------
    test('short song that completes naturally counts as 1 play', () async {
      final song = _testSong(
        id: 's5',
        title: 'Short Song',
        duration: const Duration(seconds: 15),
      );

      service.onSongStarted(song);
      for (int i = 0; i <= 15; i++) {
        service.updatePosition(Duration(seconds: i));
      }

      // 15s < 30s, so no play recorded yet
      expect(service.getSongStats('s5'), isNull);

      await service.onSongStopped(completedNaturally: true);

      final stats = service.getSongStats('s5');
      expect(stats, isNotNull);
      expect(stats!.playCount, 1);
      expect(stats.totalTime.inSeconds, 15);
    });

    test('short song that is skipped does not count', () async {
      final song = _testSong(
        id: 's6',
        title: 'Short Skipped',
        duration: const Duration(seconds: 15),
      );

      service.onSongStarted(song);
      for (int i = 0; i <= 10; i++) {
        service.updatePosition(Duration(seconds: i));
      }

      await service.onSongStopped(completedNaturally: false);

      final stats = service.getSongStats('s6');
      expect(stats!.playCount, 0);
      expect(stats.totalTime.inSeconds, 10);
    });

    // ------------------------------------------------------------------------
    // Seek handling
    // ------------------------------------------------------------------------
    test('ignores forward seek jumps when tracking time', () async {
      final song = _testSong(
        id: 's7',
        title: 'Song 7',
        duration: const Duration(minutes: 3),
      );

      service.onSongStarted(song);
      service.updatePosition(Duration.zero); // baseline
      service.updatePosition(const Duration(seconds: 1)); // +1s
      service.updatePosition(const Duration(seconds: 5)); // +4s -> seek, ignored
      service.updatePosition(const Duration(seconds: 6)); // +1s
      service.updatePosition(const Duration(seconds: 31)); // +25s -> seek, ignored

      await service.onSongStopped();

      final stats = service.getSongStats('s7');
      // Valid deltas: 0->1 (1s), 6->? nothing else counted. Total = 2s
      expect(stats!.totalTime.inSeconds, 2);
      expect(stats.playCount, 0);
    });

    test('backward seek does not inflate time', () async {
      final song = _testSong(
        id: 's8',
        title: 'Song 8',
        duration: const Duration(minutes: 3),
      );

      service.onSongStarted(song);
      service.updatePosition(Duration.zero);
      service.updatePosition(const Duration(seconds: 1)); // +1s
      service.updatePosition(const Duration(seconds: 2)); // +1s
      service.updatePosition(const Duration(seconds: 10)); // +8s -> seek, ignored
      service.updatePosition(const Duration(seconds: 5)); // backward -> ignored
      service.updatePosition(const Duration(seconds: 6)); // +1s

      await service.onSongStopped();

      final stats = service.getSongStats('s8');
      // Counted: 0->1 (+1), 1->2 (+1), 5->6 (+1) = 3s
      // 2->10 is a seek (8s > 2s), ignored.
      expect(stats!.totalTime.inSeconds, 3);
    });

    // ------------------------------------------------------------------------
    // Rapid switching & session boundaries
    // ------------------------------------------------------------------------
    test('rapid song switching does not lose or double time', () async {
      final song1 = _testSong(
        id: 's9a',
        title: 'Song A',
        duration: const Duration(minutes: 3),
      );
      final song2 = _testSong(
        id: 's9b',
        title: 'Song B',
        duration: const Duration(minutes: 3),
      );

      service.onSongStarted(song1);
      for (int i = 0; i <= 15; i++) {
        service.updatePosition(Duration(seconds: i));
      }

      // Switch to song2 (implicitly finalizes song1)
      service.onSongStarted(song2);
      await service.flushForTests();

      final stats1 = service.getSongStats('s9a');
      expect(stats1!.totalTime.inSeconds, 15);
      expect(stats1.playCount, 0);

      // Play song2 for 35s
      for (int i = 0; i <= 35; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();

      final stats2 = service.getSongStats('s9b');
      expect(stats2!.playCount, 1);
      expect(stats2.totalTime.inSeconds, 35);
    });

    test('repeat-one starts a new session', () async {
      final song = _testSong(
        id: 's10',
        title: 'Song 10',
        duration: const Duration(seconds: 25),
      );

      // First loop: completes naturally (short song < 30s)
      service.onSongStarted(song);
      for (int i = 0; i <= 25; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped(completedNaturally: true);

      // Second loop (repeat-one): 20s
      service.onSongStarted(song, isResume: false);
      for (int i = 0; i <= 20; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped(completedNaturally: true);

      final stats = service.getSongStats('s10');
      expect(stats!.playCount, 2);
      expect(stats.totalTime.inSeconds, 45);
    });

    // ------------------------------------------------------------------------
    // Persistence
    // ------------------------------------------------------------------------
    test('flushes stats to database and reloads correctly', () async {
      final song = _testSong(
        id: 's11',
        title: 'Song 11',
        duration: const Duration(minutes: 3),
      );

      service.onSongStarted(song);
      for (int i = 0; i <= 35; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();

      // Data is now in cache and DB
      final beforeReset = service.getSongStats('s11');
      expect(beforeReset!.playCount, 1);

      // Simulate app restart: reset cache and reload from DB
      service.resetForTests();
      await service.reloadFromDatabase();

      final afterReload = service.getSongStats('s11');
      expect(afterReload, isNotNull);
      expect(afterReload!.playCount, 1);
      expect(afterReload.totalTime.inSeconds, 35);
    });

    // ------------------------------------------------------------------------
    // Stale id remapping after library moves
    // ------------------------------------------------------------------------
    test(
        'remapStaleStatIdsFromLibrary collapses stale + fresh entries for the '
        'same song so artist aggregations are not double-counted', () async {
      // Simulate: user played a song under an old library path (5 plays),
      // moved the library so the song now has a new id, then played the
      // same song twice more under the new id. Without the remap, the
      // tracks tab shows two rows for the song (each with its own count)
      // and the artists tab sums them, double-counting.
      final oldSong = Song(
        id: 'stale_id',
        title: 'Same Song',
        artist: 'Same Artist',
        duration: const Duration(minutes: 3),
        filePath: '/old/path/song.mp3',
        fileSize: 1000,
        modifiedTime: DateTime(2024, 1, 1),
      );
      service.onSongStarted(oldSong);
      for (int i = 0; i <= 35; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();
      // Repeat for a second play.
      service.onSongStarted(oldSong, isResume: false);
      for (int i = 0; i <= 35; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();
      expect(service.getSongStats('stale_id')!.playCount, 2);

      // Simulate the new library path producing a different id for the
      // same song. The user plays it once under the new id.
      final newSong = Song(
        id: 'fresh_id',
        title: 'Same Song',
        artist: 'Same Artist',
        duration: const Duration(minutes: 3),
        filePath: '/new/path/song.mp3',
        fileSize: 1000,
        modifiedTime: DateTime(2024, 6, 1),
      );
      service.onSongStarted(newSong);
      for (int i = 0; i <= 35; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();
      expect(service.getSongStats('fresh_id')!.playCount, 1);

      // Pre-condition: the artists view sees both rows and the artist's
      // count is inflated to 3 across 2 unique songs.
      expect(service.getTopArtists().single.playCount, 3);
      expect(service.getTopArtists().single.uniqueSongsCount, 2);

      // Library sync: only `fresh_id` is in the current library.
      final libraryAfterMove = [
        SongModel(
          id: 'fresh_id',
          title: 'Same Song',
          artist: 'Same Artist',
          albumId: null,
          duration: 180,
        ),
      ];
      final dropped = await service
          .remapStaleStatIdsFromLibrary(libraryAfterMove);
      expect(dropped, 1, reason: 'one stale row should fold into the fresh one');

      // Stale row is gone; the merged row carries all three plays.
      expect(service.getSongStats('stale_id'), isNull);
      final merged = service.getSongStats('fresh_id')!;
      expect(merged.playCount, 3);

      // Artists view now reflects one unique song with the correct total.
      expect(service.getTopArtists().single.playCount, 3);
      expect(service.getTopArtists().single.uniqueSongsCount, 1);

      // And the change survived the round-trip to disk.
      service.resetForTests();
      await service.reloadFromDatabase();
      expect(service.getSongStats('stale_id'), isNull);
      expect(service.getSongStats('fresh_id')!.playCount, 3);
    });

    test(
        'remapStaleStatIdsFromLibrary is a no-op when every stat already '
        'matches the current library', () async {
      final song = _testSong(
        id: 'still_valid',
        title: 'Song',
        duration: const Duration(minutes: 3),
      );
      service.onSongStarted(song);
      for (int i = 0; i <= 35; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();

      final library = [
        SongModel(
          id: 'still_valid',
          title: 'Song',
          artist: 'Test Artist',
          albumId: null,
          duration: 180,
        ),
      ];
      final dropped = await service.remapStaleStatIdsFromLibrary(library);
      expect(dropped, 0);
      expect(service.getSongStats('still_valid')!.playCount, 1);
    });

    test('debounced writes batch multiple updates', () async {
      final song = _testSong(
        id: 's12',
        title: 'Song 12',
        duration: const Duration(minutes: 3),
      );

      service.onSongStarted(song);
      for (int i = 0; i <= 35; i++) {
        service.updatePosition(Duration(seconds: i));
      }
      await service.onSongStopped();

      // Now reset and reload to prove it hit the DB
      service.resetForTests();
      await service.reloadFromDatabase();

      final stats = service.getSongStats('s12');
      expect(stats, isNotNull);
      expect(stats!.playCount, 1);
      expect(stats.totalTime.inSeconds, 35);
    });
  });
}
