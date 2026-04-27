import 'package:flutter_test/flutter_test.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/song_stats.dart';
import 'package:ariami_mobile/services/song_id_remapping_service.dart';

void main() {
  group('SongIdRemappingService', () {
    late SongIdRemappingService service;

    setUp(() {
      service = SongIdRemappingService();
    });

    final librarySongs = [
      SongModel(
        id: 'new_id_1',
        title: 'Song One',
        artist: 'Artist A',
        albumId: 'album_1',
        duration: 180,
      ),
      SongModel(
        id: 'new_id_2',
        title: 'Song Two',
        artist: 'Artist B',
        albumId: 'album_2',
        duration: 240,
      ),
      SongModel(
        id: 'new_id_3',
        title: 'Song Three',
        artist: 'Artist C',
        duration: 300,
      ),
    ];

    test('remapPlaylists preserves IDs that still exist in library', () {
      final playlist = PlaylistModel(
        id: 'pl1',
        name: 'Test',
        songIds: ['new_id_1', 'new_id_2'],
        songAlbumIds: {'new_id_1': 'album_1'},
        songTitles: {'new_id_1': 'Song One'},
        songArtists: {'new_id_1': 'Artist A'},
        songDurations: {'new_id_1': 180},
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final result = service.remapPlaylists([playlist], librarySongs);

      expect(result.first.songIds, ['new_id_1', 'new_id_2']);
      expect(result.first.songAlbumIds, {'new_id_1': 'album_1'});
      // Should be the exact same instance (no mutation)
      expect(identical(result.first, playlist), isTrue);
    });

    test('remapPlaylists remaps stale IDs by title + artist + duration', () {
      final playlist = PlaylistModel(
        id: 'pl1',
        name: 'Test',
        songIds: ['old_id_1', 'old_id_2'],
        songAlbumIds: {'old_id_1': 'stale_album'},
        songTitles: {'old_id_1': 'Song One', 'old_id_2': 'Song Two'},
        songArtists: {'old_id_1': 'Artist A', 'old_id_2': 'Artist B'},
        songDurations: {'old_id_1': 180, 'old_id_2': 240},
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final result = service.remapPlaylists([playlist], librarySongs);
      final remapped = result.first;

      expect(remapped.songIds, ['new_id_1', 'new_id_2']);
      expect(remapped.songAlbumIds, {'new_id_1': 'album_1', 'new_id_2': 'album_2'});
      expect(remapped.songTitles, {'new_id_1': 'Song One', 'new_id_2': 'Song Two'});
      expect(remapped.songArtists, {'new_id_1': 'Artist A', 'new_id_2': 'Artist B'});
      expect(remapped.songDurations, {'new_id_1': 180, 'new_id_2': 240});
    });

    test('remapPlaylists preserves unmatched songs as placeholders', () {
      final playlist = PlaylistModel(
        id: 'pl1',
        name: 'Test',
        songIds: ['old_missing'],
        songTitles: {'old_missing': 'Deleted Song'},
        songArtists: {'old_missing': 'Deleted Artist'},
        songDurations: {'old_missing': 999},
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final result = service.remapPlaylists([playlist], librarySongs);

      expect(result.first.songIds, ['old_missing']);
      expect(result.first.songTitles, {'old_missing': 'Deleted Song'});
    });

    test('remapPlaylists uses duration tolerance for disambiguation', () {
      // Two songs with same title/artist but different durations
      final ambiguousLibrary = [
        SongModel(
          id: 'short_version',
          title: 'Remix',
          artist: 'DJ X',
          duration: 120,
        ),
        SongModel(
          id: 'long_version',
          title: 'Remix',
          artist: 'DJ X',
          duration: 300,
        ),
      ];

      final playlist = PlaylistModel(
        id: 'pl1',
        name: 'Test',
        songIds: ['old_id'],
        songTitles: {'old_id': 'Remix'},
        songArtists: {'old_id': 'DJ X'},
        songDurations: {'old_id': 122}, // Within tolerance of short_version
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final result = service.remapPlaylists([playlist], ambiguousLibrary);

      expect(result.first.songIds, ['short_version']);
    });

    test('remapStats remaps stale IDs by title + artist', () {
      final stats = [
        SongStats(
          songId: 'old_id_1',
          playCount: 5,
          totalTime: Duration(minutes: 10),
          songTitle: 'Song One',
          songArtist: 'Artist A',
        ),
      ];

      final result = service.remapStats(stats, librarySongs);

      expect(result.first.songId, 'new_id_1');
      expect(result.first.playCount, 5);
      expect(result.first.songTitle, 'Song One');
      expect(result.first.songArtist, 'Artist A');
      expect(result.first.albumId, 'album_1');
    });

    test('remapStats preserves valid IDs', () {
      final stats = [
        SongStats(
          songId: 'new_id_2',
          playCount: 3,
          totalTime: Duration(minutes: 5),
        ),
      ];

      final result = service.remapStats(stats, librarySongs);

      expect(result.first.songId, 'new_id_2');
      expect(identical(result.first, stats.first), isTrue);
    });

    test('remapStats keeps unmatched stats untouched', () {
      final stats = [
        SongStats(
          songId: 'old_missing',
          playCount: 1,
          totalTime: Duration(minutes: 1),
          songTitle: 'Gone',
          songArtist: 'Nobody',
        ),
      ];

      final result = service.remapStats(stats, librarySongs);

      expect(result.first.songId, 'old_missing');
    });

    test(
        'remapStats merges a stale entry into a fresh entry when both '
        'resolve to the same library song', () {
      // Reproduces the artist-stats double-counting bug: a backup entry from
      // an older library path coexists with a fresh play recorded under the
      // current path. Both must collapse onto the current id with their
      // play counts summed and date range widened.
      final firstPlayedOld = DateTime(2024, 1, 1);
      final lastPlayedOld = DateTime(2024, 6, 1);
      final firstPlayedNew = DateTime(2024, 8, 1);
      final lastPlayedNew = DateTime(2024, 12, 1);
      final stats = [
        SongStats(
          songId: 'old_id_1',
          playCount: 5,
          totalTime: const Duration(minutes: 10),
          firstPlayed: firstPlayedOld,
          lastPlayed: lastPlayedOld,
          songTitle: 'Song One',
          songArtist: 'Artist A',
        ),
        SongStats(
          songId: 'new_id_1',
          playCount: 3,
          totalTime: const Duration(minutes: 6),
          firstPlayed: firstPlayedNew,
          lastPlayed: lastPlayedNew,
          songTitle: 'Song One',
          songArtist: 'Artist A',
        ),
      ];

      final result = service.remapStats(stats, librarySongs);

      expect(result, hasLength(1));
      final merged = result.first;
      expect(merged.songId, 'new_id_1');
      expect(merged.playCount, 8);
      expect(merged.totalTime, const Duration(minutes: 16));
      expect(merged.firstPlayed, firstPlayedOld);
      expect(merged.lastPlayed, lastPlayedNew);
    });

    test('remapStats merges multiple stale entries onto one library song', () {
      // Two backup entries from different prior library moves both match
      // the same library song. saveAllStats with REPLACE would silently
      // drop one, so we have to fold them together first.
      final stats = [
        SongStats(
          songId: 'old_path_a',
          playCount: 4,
          totalTime: const Duration(minutes: 8),
          songTitle: 'Song One',
          songArtist: 'Artist A',
        ),
        SongStats(
          songId: 'old_path_b',
          playCount: 2,
          totalTime: const Duration(minutes: 4),
          songTitle: 'Song One',
          songArtist: 'Artist A',
        ),
      ];

      final result = service.remapStats(stats, librarySongs);

      expect(result, hasLength(1));
      expect(result.first.songId, 'new_id_1');
      expect(result.first.playCount, 6);
      expect(result.first.totalTime, const Duration(minutes: 12));
    });

    test('remapStats leaves distinct songs alone when no duplicates exist',
        () {
      final stats = [
        SongStats(
          songId: 'old_id_1',
          playCount: 5,
          totalTime: const Duration(minutes: 10),
          songTitle: 'Song One',
          songArtist: 'Artist A',
        ),
        SongStats(
          songId: 'old_id_2',
          playCount: 3,
          totalTime: const Duration(minutes: 6),
          songTitle: 'Song Two',
          songArtist: 'Artist B',
        ),
      ];

      final result = service.remapStats(stats, librarySongs);

      expect(result, hasLength(2));
      final byId = {for (final s in result) s.songId: s};
      expect(byId['new_id_1']!.playCount, 5);
      expect(byId['new_id_2']!.playCount, 3);
    });
  });
}
