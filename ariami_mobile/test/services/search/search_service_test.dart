import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/search_service.dart';
import 'package:ariami_mobile/services/settings/search_settings_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SearchService deduplication', () {
    final service = SearchService();

    test('deduplicates songs with same canonical metadata', () {
      final songs = <SongModel>[
        SongModel(
          id: 'song-a',
          title: 'Everything I Am',
          artist: 'Kanye West',
          albumId: 'album-1',
          duration: 228,
          trackNumber: 2,
        ),
        SongModel(
          id: 'song-b',
          title: ' everything i am ',
          artist: 'kanye west',
          albumId: 'album-1',
          duration: 228,
          trackNumber: 2,
        ),
      ];

      final deduped = service.deduplicateSongs(songs);

      expect(deduped, hasLength(1));
      expect(deduped.single.id, 'song-a');
    });

    test('keeps songs that differ by canonical metadata', () {
      final songs = <SongModel>[
        SongModel(
          id: 'song-a',
          title: 'Everything',
          artist: 'Artist',
          albumId: 'album-1',
          duration: 200,
          trackNumber: 1,
        ),
        SongModel(
          id: 'song-b',
          title: 'Everything',
          artist: 'Artist',
          albumId: 'album-1',
          duration: 204,
          trackNumber: 1,
        ),
      ];

      final deduped = service.deduplicateSongs(songs);

      expect(deduped, hasLength(2));
    });

    test('search returns deduplicated song results', () {
      final songs = <SongModel>[
        SongModel(
          id: 'song-a',
          title: 'Everyday',
          artist: 'WINNER',
          albumId: 'album-1',
          duration: 206,
        ),
        SongModel(
          id: 'song-b',
          title: 'Everyday',
          artist: 'WINNER',
          albumId: 'album-2',
          duration: 206,
          trackNumber: 8,
        ),
      ];

      final results = service.search('every', songs, const <AlbumModel>[]);

      expect(results.songs, hasLength(1));
      expect(
        results.songs.single.id,
        anyOf('song-a', 'song-b'),
      );
    });

    test('search trims whitespace-only query', () {
      final results = service.search(
        '   ',
        const <SongModel>[],
        const <AlbumModel>[],
      );

      expect(results.isEmpty, isTrue);
    });
  });

  group('SearchService matching', () {
    final service = SearchService();

    AlbumModel album({
      required String id,
      required String title,
      String artist = 'Artist',
    }) {
      return AlbumModel(
        id: id,
        title: title,
        artist: artist,
        songCount: 1,
        duration: 200,
      );
    }

    SongModel song({
      required String id,
      required String title,
      required String artist,
      String? albumId,
      int duration = 200,
    }) {
      return SongModel(
        id: id,
        title: title,
        artist: artist,
        albumId: albumId,
        duration: duration,
      );
    }

    test('single-token prefix matches title', () {
      final songs = [
        song(id: 'song-a', title: 'Everyday', artist: 'WINNER'),
      ];

      final results = service.search('every', songs, const []);

      expect(results.songs, hasLength(1));
      expect(results.songs.single.id, 'song-a');
    });

    test('album name matches song via albumId lookup', () {
      final albums = [
        album(id: 'album-1', title: 'Graduation', artist: 'Kanye West'),
      ];
      final songs = [
        song(
          id: 'song-a',
          title: 'Stronger',
          artist: 'Kanye West',
          albumId: 'album-1',
        ),
      ];

      final results = service.search('graduation', songs, albums);

      expect(results.songs, hasLength(1));
      expect(results.songs.single.id, 'song-a');
    });

    test('multi-word cross-field query matches song', () {
      final albums = [
        album(id: 'album-1', title: 'Graduation', artist: 'Kanye West'),
      ];
      final songs = [
        song(
          id: 'song-a',
          title: 'Everything I Am',
          artist: 'Kanye West',
          albumId: 'album-1',
        ),
      ];

      final results = service.search('kanye everything', songs, albums);

      expect(results.songs, hasLength(1));
      expect(results.songs.single.id, 'song-a');
    });

    test('multi-word query returns empty when a token does not match', () {
      final albums = [
        album(id: 'album-1', title: 'Graduation', artist: 'Kanye West'),
      ];
      final songs = [
        song(
          id: 'song-a',
          title: 'Stronger',
          artist: 'Kanye West',
          albumId: 'album-1',
        ),
      ];

      final results = service.search('kanye nonexistent', songs, albums);

      expect(results.songs, isEmpty);
    });

    test('normalizes whitespace and case in query', () {
      final songs = [
        song(id: 'song-a', title: 'Everyday', artist: 'WINNER'),
      ];

      final results = service.search('  EVERY  ', songs, const []);

      expect(results.songs, hasLength(1));
      expect(results.songs.single.id, 'song-a');
    });

    test('song without albumId cannot match on album name', () {
      final albums = [
        album(id: 'album-1', title: 'Graduation', artist: 'Kanye West'),
      ];
      final songs = [
        song(
          id: 'song-a',
          title: 'Stronger',
          artist: 'Kanye West',
        ),
      ];

      final results = service.search('graduation', songs, albums);

      expect(results.songs, isEmpty);
    });

    test('multi-word album query matches album section', () {
      final albums = [
        album(
          id: 'album-1',
          title: 'The Dark Side of the Moon',
          artist: 'Pink Floyd',
        ),
      ];

      final results = service.search('dark side', const [], albums);

      expect(results.albums, hasLength(1));
      expect(results.albums.single.id, 'album-1');
    });

    test('typo-tolerant query matches song title', () {
      final songs = [
        song(id: 'song-a', title: 'Mirrors', artist: 'Justin Timberlake'),
      ];

      final results = service.search('mirrirs', songs, const []);

      expect(results.songs, hasLength(1));
      expect(results.songs.single.id, 'song-a');
    });

    test('typo-tolerant matches rank below exact and substring matches', () {
      final songs = [
        song(id: 'song-fuzzy', title: 'Mirrors', artist: 'Artist'),
        song(id: 'song-exact', title: 'Mirrirs', artist: 'Artist'),
        song(id: 'song-substring', title: 'Big Mirrirs Song', artist: 'Artist'),
      ];

      final results = service.search('mirrirs', songs, const []);

      expect(
        results.songs.map((song) => song.id),
        ['song-exact', 'song-substring', 'song-fuzzy'],
      );
    });

    test('typo-tolerant query matches album title', () {
      final albums = [
        album(id: 'album-1', title: 'Mirrors'),
      ];

      final results = service.search('mirrirs', const [], albums);

      expect(results.albums, hasLength(1));
      expect(results.albums.single.id, 'album-1');
    });
  });

  group('SearchService recent songs dynamic limit & trimming', () {
    late SearchSettingsService settingsService;
    late SearchService service;

    SongModel testSong(String id, String title) {
      return SongModel(
        id: id,
        title: title,
        artist: 'Artist',
        duration: 180,
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initializeSharedPrefs();
      settingsService = SearchSettingsService();
      settingsService.resetForTesting();
      service = SearchService(settingsService: settingsService);
    });

    test('defaults maxRecentSongs to 30', () {
      expect(service.maxRecentSongs, 30);
    });

    test('addRecentSong respects standard 30 limit', () async {
      for (var i = 0; i < 35; i++) {
        await service.addRecentSong(testSong('s$i', 'Song $i'));
      }

      final recent = await service.getRecentSongs();
      expect(recent.length, 30);
      // Newest song should be at index 0
      expect(recent.first.id, 's34');
      // Oldest retained should be s5
      expect(recent.last.id, 's5');
    });

    test('addRecentSong respects custom limit (e.g. 10)', () async {
      await settingsService.setRecentSearchesLimit(isCustom: true, customLimit: 10);
      expect(service.maxRecentSongs, 10);

      for (var i = 0; i < 15; i++) {
        await service.addRecentSong(testSong('s$i', 'Song $i'));
      }

      final recent = await service.getRecentSongs();
      expect(recent.length, 10);
      expect(recent.first.id, 's14');
      expect(recent.last.id, 's5');
    });

    test('insertRecentSongAt respects custom limit', () async {
      await settingsService.setRecentSearchesLimit(isCustom: true, customLimit: 5);

      for (var i = 0; i < 5; i++) {
        await service.addRecentSong(testSong('s$i', 'Song $i'));
      }

      // Insert at index 1
      await service.insertRecentSongAt(testSong('inserted', 'Inserted'), 1);

      final recent = await service.getRecentSongs();
      expect(recent.length, 5);
      expect(recent[0].id, 's4');
      expect(recent[1].id, 'inserted');
      // The last one pushed out
      expect(recent.any((s) => s.id == 's0'), isFalse);
    });

    test('getRecentSongs trims stored songs if limit is reduced', () async {
      // Add 20 songs under default limit
      for (var i = 0; i < 20; i++) {
        await service.addRecentSong(testSong('s$i', 'Song $i'));
      }
      expect((await service.getRecentSongs()).length, 20);

      // Change limit to 8
      await settingsService.setRecentSearchesLimit(isCustom: true, customLimit: 8);

      final recent = await service.getRecentSongs();
      expect(recent.length, 8);
      expect(recent.first.id, 's19');
      expect(recent.last.id, 's12');
    });

    test('trimRecentSongs trims to specified or dynamic limit', () async {
      for (var i = 0; i < 15; i++) {
        await service.addRecentSong(testSong('s$i', 'Song $i'));
      }

      // Explicit limit of 6
      final trimmed = await service.trimRecentSongs(6);
      expect(trimmed.length, 6);
      expect((await service.getRecentSongs()).length, 6);

      // When limit is already >= stored count, trimRecentSongs is a no-op
      final untrimmed = await service.trimRecentSongs(10);
      expect(untrimmed.length, 6);
    });

    test('getRecentSongs skips corrupt JSON entries without throwing', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(SearchService.recentSongsKey, [
        '{"id":"valid1","title":"Valid 1","artist":"A","duration":100}',
        'not valid json',
        '{"invalid_shape":true}',
        '{"id":"valid2","title":"Valid 2","artist":"A","duration":100}',
      ]);

      final songs = await service.getRecentSongs();
      expect(songs.length, 2);
      expect(songs[0].id, 'valid1');
      expect(songs[1].id, 'valid2');
    });

    test('trimRecentSongs handles negative or zero limit safely', () async {
      for (var i = 0; i < 5; i++) {
        await service.addRecentSong(testSong('s$i', 'Song $i'));
      }

      // Negative limit clamps to 0
      final trimmed = await service.trimRecentSongs(-3);
      expect(trimmed, isEmpty);
      expect(await service.getRecentSongs(), isEmpty);
    });

    test('addRecentSong safely recovers when stored entries are corrupt', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(SearchService.recentSongsKey, ['corrupted']);

      await service.addRecentSong(testSong('new', 'New'));
      final songs = await service.getRecentSongs();
      expect(songs.length, 1);
      expect(songs.first.id, 'new');
    });
  });
}
