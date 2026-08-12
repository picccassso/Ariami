import 'package:ariami_mobile/services/library/library_genre_index.dart';
import 'package:ariami_mobile/widgets/library/genre_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ranks album genres by track count and facets by album breadth', () {
    final index = LibraryGenreIndex.build(const <LibraryGenreSource>[
      LibraryGenreSource(albumId: 'album-1', genre: 'Rock, Jazz'),
      LibraryGenreSource(albumId: 'album-1', genre: 'Rock'),
      LibraryGenreSource(albumId: 'album-2', genre: 'Jazz'),
      LibraryGenreSource(albumId: 'album-3', genre: 'Rock'),
    ]);

    expect(index.albumGenres['album-1'], ['rock', 'jazz']);
    expect(index.genres, ['jazz', 'rock'],
        reason: 'equal album breadth uses an alphabetical tie-break');
    expect(index.genreAlbums['rock'], {'album-1', 'album-3'});
  });

  test('genre labels stay compact and retain a selected collapsed facet', () {
    expect(genreSummary(['rock']), 'Rock');
    expect(genreSummary(['rock', 'jazz', 'funk']), 'Rock +2');
    expect(genreDetail(['jazz', 'rock']), 'Jazz · Rock');
    expect(
      visibleGenreFacets(
        List<String>.generate(10, (index) => 'genre$index'),
        'genre9',
        limit: 3,
        expanded: false,
      ),
      ['genre0', 'genre1', 'genre2', 'genre9'],
    );
  });
}
