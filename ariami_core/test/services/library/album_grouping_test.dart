import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/album_builder.dart';
import 'package:ariami_core/services/library/album_grouping.dart';
import 'package:ariami_core/services/library/album_identity.dart';
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

    test('uses track artist when album artist is a YouTube channel name', () {
      expect(
        albumGroupingArtist(_song(
          path: '/eminem.mp3',
          album: 'The Marshall Mathers LP',
          artist: 'Eminem',
          albumArtist: 'EminemMusic',
        )),
        'Eminem',
      );
      expect(
        albumGroupingArtist(_song(
          path: '/nf.mp3',
          album: 'The Search',
          artist: 'NF',
          albumArtist: 'NFrealmusic',
        )),
        'NF',
      );
    });

    test('normalizes Eminem vs Eminem, Jessie Reyez to Eminem', () {
      final solo = albumGroupingArtist(
          _song(path: '/1.mp3', album: 'K', artist: 'Eminem'));
      final duo = albumGroupingArtist(
        _song(path: '/2.mp3', album: 'K', artist: 'Eminem, Jessie Reyez'),
      );
      expect(solo, 'Eminem');
      expect(duo, 'Eminem');
      expect(solo, duo);
    });

    test('normalizes Russ vs Russ, Bibi Bourelly to Russ', () {
      final a = albumGroupingArtist(
          _song(path: '/1.mp3', album: 'S', artist: 'Russ'));
      final b = albumGroupingArtist(
        _song(path: '/2.mp3', album: 'S', artist: 'Russ, Bibi Bourelly'),
      );
      expect(a, 'Russ');
      expect(b, 'Russ');
    });

    test('strips feat. / ft. / featuring suffix', () {
      expect(
        albumGroupingArtist(_song(
            path: '/x.mp3', album: 'A', artist: 'Eminem feat. Jessie Reyez')),
        'Eminem',
      );
      expect(
        albumGroupingArtist(
            _song(path: '/y.mp3', album: 'A', artist: 'Russ ft. Guest')),
        'Russ',
      );
      expect(
        albumGroupingArtist(
            _song(path: '/z.mp3', album: 'A', artist: 'A featuring B')),
        'A',
      );
    });

    test('returns null when track artist missing', () {
      expect(albumGroupingArtist(_song(path: '/x.mp3', album: 'OnlyAlbum')),
          isNull);
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
        _song(
            path: '/m3.mp3', album: 'Kamikaze', artist: 'Eminem, Jessie Reyez'),
      ];
      final library = AlbumBuilder().buildLibrary(songs);
      expect(library.albums.length, 1);
      expect(library.albums.values.first.songs.length, 3);
    });

    test('displays track artist instead of YouTube channel album artist', () {
      final songs = [
        _song(
          path: '/mm1.mp3',
          album: 'The Marshall Mathers LP',
          title: 'Public Service Announcement',
          artist: 'Eminem',
          albumArtist: 'EminemMusic',
          trackNumber: 1,
        ),
        _song(
          path: '/mm2.mp3',
          album: 'The Marshall Mathers LP',
          title: 'Kill You',
          artist: 'Eminem',
          albumArtist: 'EminemMusic',
          trackNumber: 2,
        ),
        _song(
          path: '/mm3.mp3',
          album: 'The Marshall Mathers LP',
          title: 'Steve Berman',
          artist: 'Steve Berman',
          albumArtist: 'EminemMusic',
          trackNumber: 3,
        ),
      ];

      final library = AlbumBuilder().buildLibrary(songs);
      final album = library.albums.values.single;

      expect(album.artist, 'Eminem');
      expect(album.id, generateAlbumId(album.title, 'Eminem'));
      expect(album.songs, hasLength(3));
    });

    test('keeps legitimate shared album artist labels', () {
      final songs = [
        _song(
          path: '/label1.mp3',
          album: 'Shared Hits',
          title: 'First',
          artist: 'Artist One',
          albumArtist: 'Shared Label',
        ),
        _song(
          path: '/label2.mp3',
          album: 'Shared Hits',
          title: 'Second',
          artist: 'Artist Two',
          albumArtist: 'Shared Label',
        ),
      ];

      final library = AlbumBuilder().buildLibrary(songs);

      expect(library.albums.values.single.artist, 'Shared Label');
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

  group('generateAlbumId parity', () {
    test(
        'matches AlbumBuilder id for multi-artist album below compilation threshold',
        () {
      final songs = [
        _song(
          path: '/a1.mp3',
          album: 'Hits',
          artist: 'Artist One',
          albumArtist: 'Shared Label',
        ),
        _song(
          path: '/a2.mp3',
          album: 'Hits',
          artist: 'Artist Two',
          albumArtist: 'Shared Label',
        ),
        _song(
          path: '/a3.mp3',
          album: 'Hits',
          artist: 'Artist Three',
          albumArtist: 'Shared Label',
        ),
        _song(
          path: '/a4.mp3',
          album: 'Hits',
          artist: 'Artist Four',
          albumArtist: 'Shared Label',
        ),
      ];

      final library = AlbumBuilder().buildLibrary(songs);
      final album = library.albums.values.single;

      expect(album.artist, 'Shared Label');
      expect(album.id, generateAlbumId(album.title, album.artist));
    });

    test(
        'matches AlbumBuilder id for five track artists with shared album artist',
        () {
      final songs = [
        _song(
          path: '/c1.mp3',
          album: 'Now',
          artist: 'Artist 1',
          albumArtist: 'Shared Label',
        ),
        _song(
          path: '/c2.mp3',
          album: 'Now',
          artist: 'Artist 2',
          albumArtist: 'Shared Label',
        ),
        _song(
          path: '/c3.mp3',
          album: 'Now',
          artist: 'Artist 3',
          albumArtist: 'Shared Label',
        ),
        _song(
          path: '/c4.mp3',
          album: 'Now',
          artist: 'Artist 4',
          albumArtist: 'Shared Label',
        ),
        _song(
          path: '/c5.mp3',
          album: 'Now',
          artist: 'Artist 5',
          albumArtist: 'Shared Label',
        ),
      ];

      final library = AlbumBuilder().buildLibrary(songs);
      final album = library.albums.values.single;

      expect(album.artist, 'Shared Label');
      expect(album.id, generateAlbumId(album.title, album.artist));
    });

    test('matches AlbumBuilder id when album artist tag contains various', () {
      final songs = [
        _song(
          path: '/v1.mp3',
          album: 'Soundtrack',
          artist: 'Performer A',
          albumArtist: 'Various Artists',
        ),
        _song(
          path: '/v2.mp3',
          album: 'Soundtrack',
          artist: 'Performer B',
          albumArtist: 'Various Artists',
        ),
      ];

      final library = AlbumBuilder().buildLibrary(songs);
      final album = library.albums.values.single;

      expect(album.artist, 'Various Artists');
      expect(album.id, generateAlbumId(album.title, album.artist));
    });

    test('final album id differs from naive grouping-key hash for compilations',
        () {
      final songs = [
        _song(
          path: '/g1.mp3',
          album: 'Mix',
          artist: 'Artist 1',
          albumArtist: 'Various Artists',
        ),
        _song(
          path: '/g2.mp3',
          album: 'Mix',
          artist: 'Artist 2',
          albumArtist: 'Various Artists',
        ),
      ];

      final groupingKey = albumGroupingKey(songs.first);
      expect(groupingKey, isNotNull);

      final library = AlbumBuilder().buildLibrary(songs);
      final album = library.albums.values.single;

      expect(album.artist, 'Various Artists');
      expect(album.id, generateAlbumId(album.title, album.artist));
      expect(album.id, isNot(generateAlbumId(groupingKey!, '')));
    });

    test('single-song album below threshold stays standalone without album id',
        () {
      final songs = [
        _song(path: '/solo.mp3', album: 'Solo Album', artist: 'Solo Artist'),
      ];

      final library = AlbumBuilder().buildLibrary(songs);
      expect(library.albums, isEmpty);
      expect(library.standaloneSongs, hasLength(1));
    });
  });
}
