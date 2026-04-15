import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/album_builder.dart';
import 'package:ariami_core/services/library/album_grouping.dart';
import 'package:test/test.dart';

SongMetadata _song({
  required String path,
  String? album,
  String? title,
  String? artist,
  String? albumArtist,
  int? trackNumber,
}) {
  return SongMetadata(
    filePath: path,
    album: album,
    title: title,
    artist: artist,
    albumArtist: albumArtist,
    trackNumber: trackNumber,
  );
}

void main() {
  group('albumGroupingArtist', () {
    test('uses album artist when set', () {
      expect(
        albumGroupingArtist(_song(
          path: '/a.mp3',
          album: 'LP',
          artist: 'Eminem, D12',
          albumArtist: 'Eminem',
        )),
        'Eminem',
      );
    });

    test('normalizes Eminem vs Eminem, Jessie Reyez to Eminem', () {
      final solo = albumGroupingArtist(_song(path: '/1.mp3', album: 'K', artist: 'Eminem'));
      final duo = albumGroupingArtist(
        _song(path: '/2.mp3', album: 'K', artist: 'Eminem, Jessie Reyez'),
      );
      expect(solo, 'Eminem');
      expect(duo, 'Eminem');
      expect(solo, duo);
    });

    test('normalizes Russ vs Russ, Bibi Bourelly to Russ', () {
      final a = albumGroupingArtist(_song(path: '/1.mp3', album: 'S', artist: 'Russ'));
      final b = albumGroupingArtist(
        _song(path: '/2.mp3', album: 'S', artist: 'Russ, Bibi Bourelly'),
      );
      expect(a, 'Russ');
      expect(b, 'Russ');
    });

    test('strips feat. / ft. / featuring suffix', () {
      expect(
        albumGroupingArtist(_song(path: '/x.mp3', album: 'A', artist: 'Eminem feat. Jessie Reyez')),
        'Eminem',
      );
      expect(
        albumGroupingArtist(_song(path: '/y.mp3', album: 'A', artist: 'Russ ft. Guest')),
        'Russ',
      );
      expect(
        albumGroupingArtist(_song(path: '/z.mp3', album: 'A', artist: 'A featuring B')),
        'A',
      );
    });

    test('returns null when track artist missing', () {
      expect(albumGroupingArtist(_song(path: '/x.mp3', album: 'OnlyAlbum')), isNull);
    });
  });

  group('albumGroupingKey', () {
    test('merges varying TPE1 into one key for same album title', () {
      final kEminem = albumGroupingKey(_song(
        path: '/a.mp3',
        album: 'The Marshall Mathers LP',
        artist: 'Eminem',
      ));
      final kEminemD12 = albumGroupingKey(_song(
        path: '/b.mp3',
        album: 'The Marshall Mathers LP',
        artist: 'Eminem, D12',
      ));
      expect(kEminem, kEminemD12);
      expect(kEminem, 'the marshall mathers lp|||eminem');
    });

    test('null when album missing', () {
      expect(albumGroupingKey(_song(path: '/a.mp3', artist: 'X')), isNull);
    });

    test('null when no artist derivable', () {
      expect(albumGroupingKey(_song(path: '/a.mp3', album: 'X')), isNull);
    });

    test('normalizes noisy album prefix', () {
      expect(normalizeAlbumTitle('Album - BULLY'), 'BULLY');
      expect(normalizeAlbumTitle('  album:  Test  '), 'Test');
    });
  });

  group('AlbumBuilder integration', () {
    test('single album from tracks with different TPE1 strings', () {
      final songs = [
        _song(path: '/m1.mp3', album: 'Kamikaze', artist: 'Eminem'),
        _song(path: '/m2.mp3', album: 'Kamikaze', artist: 'Eminem'),
        _song(path: '/m3.mp3', album: 'Kamikaze', artist: 'Eminem, Jessie Reyez'),
      ];
      final library = AlbumBuilder().buildLibrary(songs);
      expect(library.albums.length, 1);
      expect(library.albums.values.first.songs.length, 3);
    });

    test('keeps legitimate album even if title contains playlist word', () {
      final songs = [
        _song(
          path: '/l1.mp3',
          album: 'The Playlist',
          title: 'Song 1',
          artist: 'Same Artist',
          trackNumber: 1,
        ),
        _song(
          path: '/l2.mp3',
          album: 'The Playlist',
          title: 'Song 2',
          artist: 'Same Artist',
          trackNumber: 2,
        ),
      ];

      final library = AlbumBuilder().buildLibrary(songs);
      expect(library.albums.length, 1);
      expect(library.albums.values.first.title, 'The Playlist');
      expect(library.albums.values.first.songs.length, 2);
    });
  });
}
