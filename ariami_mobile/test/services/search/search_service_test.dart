import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
