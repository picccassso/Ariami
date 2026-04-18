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
}
