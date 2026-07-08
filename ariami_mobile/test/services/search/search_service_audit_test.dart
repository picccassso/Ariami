import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression harness for mobile search behaviour, originally written as an
/// audit of the pre-shared-engine implementation. The former `GAP:` cases
/// (transliteration, keyboard-layout correction, diacritic folding,
/// punctuation stripping, Cyrillic fuzzy) were flipped to their fixed
/// expectations when search moved to the shared engine in ariami_core.
void main() {
  final service = SearchService();

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

  PlaylistModel playlist({required String id, required String name}) {
    return PlaylistModel(
      id: id,
      name: name,
      songIds: const <String>[],
      createdAt: DateTime(2026),
      modifiedAt: DateTime(2026),
    );
  }

  group('case-insensitivity and field coverage', () {
    test('uppercase Latin query matches lowercase-stored title', () {
      final songs = [song(id: 's1', title: 'Everyday', artist: 'WINNER')];

      final results = service.search('EVERYDAY', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });

    test('artist-only query returns the song', () {
      final songs = [
        song(id: 's1', title: 'Stronger', artist: 'Kanye West'),
      ];

      final results = service.search('kanye', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });

    test('album-artist query returns the song via albumId lookup', () {
      final albums = [
        album(id: 'a1', title: 'Compilation Vol 1', artist: 'Various Names'),
      ];
      final songs = [
        song(id: 's1', title: 'Opener', artist: 'Someone', albumId: 'a1'),
      ];

      final results = service.search('various', songs, albums);

      expect(results.songs.map((s) => s.id), ['s1']);
    });

    test('album search matches on album artist', () {
      final albums = [
        album(id: 'a1', title: 'The Wall', artist: 'Pink Floyd'),
      ];

      final results = service.search('pink floyd', const [], albums);

      expect(results.albums.map((a) => a.id), ['a1']);
    });

    test('playlists are searchable by name, including Cyrillic', () {
      final playlists = [
        playlist(id: 'p1', name: 'Дорожная музыка'),
        playlist(id: 'p2', name: 'Workout Mix'),
      ];

      expect(
        service
            .search('workout', const [], const [], playlists: playlists)
            .playlists
            .map((p) => p.id),
        ['p2'],
      );
      expect(
        service
            .search('дорожная', const [], const [], playlists: playlists)
            .playlists
            .map((p) => p.id),
        ['p1'],
      );
    });
  });

  group('Cyrillic', () {
    test('exact Cyrillic query matches Cyrillic artist', () {
      final songs = [
        song(id: 's1', title: 'Группа крови', artist: 'Кино'),
      ];

      final results = service.search('кино', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });

    test('Cyrillic matching is case-insensitive (Unicode toLowerCase)', () {
      final songs = [
        song(id: 's1', title: 'Группа крови', artist: 'КИНО'),
      ];

      final results = service.search('Кино', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });

    test('Cyrillic results rank exact before prefix before substring', () {
      final songs = [
        song(id: 'substring', title: 'Моё кино навсегда', artist: 'Артист'),
        song(id: 'prefix', title: 'Кинотеатр', artist: 'Артист'),
        song(id: 'exact', title: 'Песня', artist: 'Кино'),
      ];

      final results = service.search('кино', songs, const []);

      expect(
        results.songs.map((s) => s.id),
        ['exact', 'prefix', 'substring'],
      );
    });

    test('Cyrillic typos are matched by the fuzzy tier', () {
      // 'перамен' — one substitution from 'перемен'.
      final songs = [
        song(id: 's1', title: 'Перемен', artist: 'Кино'),
      ];

      final results = service.search('перамен', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });
  });

  group('accents and punctuation', () {
    test('beyonce finds Beyoncé via diacritic folding (not fuzzy)', () {
      // Folding happens in normalization, so the accented artist matches at
      // full rank alongside the unaccented one instead of trailing as a
      // fuzzy afterthought.
      final songs = [
        song(id: 'accented', title: 'Halo', artist: 'Beyoncé'),
        song(id: 'plain', title: 'Tribute', artist: 'Beyonce'),
      ];

      final results = service.search('beyonce', songs, const []);

      expect(results.songs.map((s) => s.id), ['accented', 'plain']);
    });

    test('medial accents fold too (motorhead finds Motörhead)', () {
      final songs = [
        song(id: 's1', title: 'Ace of Spades', artist: 'Motörhead'),
      ];

      final results = service.search('motorhead', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });

    test('apostrophes are stripped (dont finds Don\'t)', () {
      final songs = [
        song(id: 's1', title: "Don't Stop Me Now", artist: 'Queen'),
      ];

      final results = service.search('dont', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });

    test('query containing the same punctuation still matches', () {
      final songs = [
        song(id: 's1', title: "Don't Stop Me Now", artist: 'Queen'),
      ];

      final results = service.search("don't", songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });
  });

  group('transliteration and keyboard layout', () {
    test('Latin transliteration matches Cyrillic (kino finds Кино)', () {
      final songs = [
        song(id: 's1', title: 'Группа крови', artist: 'Кино'),
      ];

      final results = service.search('kino', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });

    test('multi-word transliteration (viktor tsoy finds Виктор Цой)', () {
      final songs = [
        song(id: 's1', title: 'Кончится лето', artist: 'Виктор Цой'),
      ];

      final results = service.search('viktor tsoy', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });

    test('wrong-keyboard-layout queries are corrected (rbyj finds Кино)', () {
      final songs = [
        song(id: 's1', title: 'Группа крови', artist: 'Кино'),
      ];

      final results = service.search('rbyj', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });

    test('assisted matches rank below direct matches', () {
      final songs = [
        song(id: 'assisted', title: 'Кино', artist: 'Артист'),
        song(id: 'direct', title: 'Kino Club', artist: 'Artist'),
      ];

      final results = service.search('kino', songs, const []);

      expect(results.songs.map((s) => s.id), ['direct', 'assisted']);
    });
  });

  group('ranking', () {
    test('Latin results rank exact → prefix → substring → fuzzy', () {
      final songs = [
        song(id: 'fuzzy', title: 'Mirrirs', artist: 'Artist'),
        song(id: 'substring', title: 'Big Mirrors Poster', artist: 'Artist'),
        song(id: 'prefix', title: 'Mirrorsong', artist: 'Artist'),
        song(id: 'exact', title: 'Mirrors', artist: 'Artist'),
      ];

      final results = service.search('mirrors', songs, const []);

      expect(
        results.songs.map((s) => s.id),
        ['exact', 'prefix', 'substring', 'fuzzy'],
      );
    });

    test('multi-word cross-field query matches and ranks', () {
      final songs = [
        song(id: 's1', title: 'Stronger', artist: 'Kanye West'),
        song(id: 's2', title: 'Something Else', artist: 'Kanye West'),
      ];

      final results = service.search('kanye stronger', songs, const []);

      expect(results.songs.map((s) => s.id), ['s1']);
    });
  });
}
