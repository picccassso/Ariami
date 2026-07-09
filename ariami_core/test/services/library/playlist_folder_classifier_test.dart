import 'package:test/test.dart';

import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/playlist_folder_classifier.dart';

void main() {
  const classifier = PlaylistFolderClassifier();
  const root = '/music';

  SongMetadata song(
    String path, {
    String? title,
    String? artist,
    String? albumArtist,
    String? album,
    int? trackNumber,
  }) {
    return SongMetadata(
      filePath: path,
      title: title,
      artist: artist,
      albumArtist: albumArtist,
      album: album,
      trackNumber: trackNumber,
    );
  }

  /// N loose files in [folder], each from its own album/artist.
  List<SongMetadata> mixedFolder(String folder, int count) {
    return [
      for (var i = 0; i < count; i++)
        song(
          '$folder/track$i.mp3',
          title: 'Track $i',
          artist: 'Artist $i',
          album: 'Album $i',
          trackNumber: (i % 3) + 1, // duplicated numbers, playlist-shaped
        ),
    ];
  }

  /// N loose files spread round-robin over [albums] albums and [artists]
  /// artists — a realistic "collected from everywhere" playlist shape.
  List<SongMetadata> spreadFolder(
    String folder,
    int count, {
    required int albums,
    required int artists,
  }) {
    return [
      for (var i = 0; i < count; i++)
        song(
          '$folder/track$i.mp3',
          title: 'Track $i',
          artist: 'Artist ${i % artists}',
          album: 'Album ${i % albums}',
          trackNumber: (i % 4) + 1,
        ),
    ];
  }

  group('auto-imports (high confidence)', () {
    test('a playlist-named mixed folder with enough files', () {
      for (final name in ['Gym', 'Road Trip', 'Liked Songs', 'Car Mix',
          'Favourites', 'Party']) {
        final result = classifier.classify(
          songs: spreadFolder('$root/$name', 10, albums: 5, artists: 5),
          libraryRootPath: root,
        );

        expect(result.autoImports.map((s) => s.name), [name],
            reason: '"$name" is playlist-named, has 10 mixed files from 5 '
                'albums/artists — strong evidence, should auto-import');
        expect(result.suggestions, isEmpty,
            reason: 'auto-imported folders are not also suggested');
      }
    });

    test('an unnamed folder with very high artist/album diversity', () {
      final result = classifier.classify(
        songs: spreadFolder('$root/Stuff', 50, albums: 25, artists: 30),
        libraryRootPath: root,
      );

      expect(result.autoImports, hasLength(1));
      final s = result.autoImports.single;
      expect(s.name, 'Stuff');
      expect(s.songCount, 50);
      expect(s.albumCount, 25);
      expect(s.artistCount, 30);
      expect(s.missingTags, isFalse);
      expect(result.suggestions, isEmpty);
    });

    test('an untagged folder when playlist-named with enough files', () {
      final result = classifier.classify(
        songs: [
          for (var i = 0; i < 9; i++) song('$root/Gym Mix/track$i.mp3'),
        ],
        libraryRootPath: root,
      );

      expect(result.autoImports, hasLength(1));
      expect(result.autoImports.single.missingTags, isTrue,
          reason: 'untagged playlist-named dumps import — their tracks '
              'would stay standalone anyway');
    });

    test('never a folder the user chose to ignore', () {
      final result = classifier.classify(
        songs: spreadFolder('$root/Gym', 10, albums: 5, artists: 5),
        libraryRootPath: root,
        ignoredFolderPaths: {'$root/Gym'},
      );

      expect(result.autoImports, isEmpty);
      expect(result.suggestions, isEmpty,
          reason: 'an ignore decision silences the folder entirely');
    });

    test('nested auto-imports collapse into the outermost folder', () {
      final result = classifier.classify(
        songs: [
          ...spreadFolder('$root/Gym', 10, albums: 5, artists: 5),
          ...spreadFolder('$root/Gym/Warmup Mix', 10, albums: 5, artists: 5),
        ],
        libraryRootPath: root,
      );

      expect(result.autoImports.map((s) => s.folderPath), ['$root/Gym']);
      expect(result.suggestions, isEmpty,
          reason: 'the inner folder is neither imported nor suggested — '
              'its files belong to the outer playlist');
    });
  });

  group('suggests (medium confidence)', () {
    test('a mixed folder below the auto-import size', () {
      final result = classifier.classify(
        songs: mixedFolder('$root/Old iPod Dump', 6),
        libraryRootPath: root,
      );

      expect(result.autoImports, isEmpty,
          reason: '6 files is below the auto-import minimum');
      expect(result.suggestions, hasLength(1));
      final s = result.suggestions.single;
      expect(s.folderPath, '$root/Old iPod Dump');
      expect(s.name, 'Old iPod Dump');
      expect(s.songCount, 6);
      expect(s.albumCount, 6);
      expect(s.artistCount, 6);
      expect(s.missingTags, isFalse);
      expect(s.reasons, isNotEmpty);
    });

    test('an unnamed folder with only moderate diversity', () {
      // 12 files over 4 albums/4 artists: diverse enough to suggest, but
      // without a playlist-like name it is not "very high diversity".
      final result = classifier.classify(
        songs: spreadFolder('$root/From Laptop', 12, albums: 4, artists: 4),
        libraryRootPath: root,
      );

      expect(result.autoImports, isEmpty);
      expect(result.suggestions, hasLength(1));
      expect(result.suggestions.single.name, 'From Laptop');
    });

    test('a small playlist-named folder with many album tags', () {
      final result = classifier.classify(
        songs: mixedFolder('$root/Road Trip', 6),
        libraryRootPath: root,
      );

      expect(result.autoImports, isEmpty);
      expect(result.suggestions, hasLength(1));
      expect(result.suggestions.single.name, 'Road Trip');
      expect(
        result.suggestions.single.reasons,
        contains('folder name looks like a playlist'),
      );
    });

    test('a small missing-tag folder ONLY when its name is playlist-like, '
        'flagged for review', () {
      List<SongMetadata> untagged(String folder) => [
            for (var i = 0; i < 6; i++) song('$folder/track$i.mp3'),
          ];

      final playlistLike = classifier.classify(
        songs: untagged('$root/Gym Mix'),
        libraryRootPath: root,
      );
      expect(playlistLike.autoImports, isEmpty,
          reason: '6 untagged files is below the auto-import minimum');
      expect(playlistLike.suggestions, hasLength(1));
      expect(playlistLike.suggestions.single.missingTags, isTrue);
      expect(
        playlistLike.suggestions.single.reasons.join(' '),
        contains('review before importing'),
      );

      final anonymous = classifier.classify(
        songs: untagged('$root/New Folder'),
        libraryRootPath: root,
      );
      expect(anonymous.suggestions, isEmpty,
          reason: 'untagged folders without a playlist-like name are left '
              'alone');
      expect(anonymous.autoImports, isEmpty);
    });
  });

  group('never touches (album protection)', () {
    void expectUntouched(List<SongMetadata> songs, {required String reason}) {
      final result = classifier.classify(
        songs: songs,
        libraryRootPath: root,
      );
      expect(result.autoImports, isEmpty, reason: reason);
      expect(result.suggestions, isEmpty, reason: reason);
    }

    test('a normal Artist/Album folder', () {
      expectUntouched(
        [
          for (var i = 1; i <= 10; i++)
            song(
              '$root/Kanye West/808s and Heartbreak/$i.mp3',
              title: 'Song $i',
              artist: 'Kanye West',
              album: '808s and Heartbreak',
              trackNumber: i,
            ),
        ],
        reason: 'a single dominant album is an album, never a playlist',
      );
    });

    test('a Various Artists compilation despite many track artists', () {
      expectUntouched(
        [
          for (var i = 1; i <= 12; i++)
            song(
              '$root/Various Artists/Now Album/$i.mp3',
              title: 'Hit $i',
              artist: 'Pop Artist $i',
              albumArtist: 'Various Artists',
              album: 'Now Album',
              trackNumber: i,
            ),
        ],
        reason: 'Various Artists compilations are protected',
      );
    });

    test('a compilation spread over several albums', () {
      expectUntouched(
        [
          for (var i = 0; i < 8; i++)
            song(
              '$root/Charts/$i.mp3',
              title: 'Hit $i',
              artist: 'Artist $i',
              albumArtist: 'Various Artists',
              album: 'NOW ${90 + i}',
            ),
        ],
        reason: 'compilation tagging wins even with album diversity',
      );
    });

    test('an artist dump with many albums from the same artist', () {
      expectUntouched(
        [
          for (var i = 0; i < 12; i++)
            song(
              '$root/Metallica Everything/$i.mp3',
              title: 'Song $i',
              artist: 'Metallica',
              albumArtist: 'Metallica',
              album: 'Album ${i % 6}',
            ),
        ],
        reason: 'a single dominant album artist means an artist folder, '
            'not a playlist',
      );
    });

    test('a single-album folder just because it has a playlist-like name',
        () {
      expectUntouched(
        [
          for (var i = 1; i <= 9; i++)
            song(
              '$root/Party/$i.mp3',
              title: 'Song $i',
              artist: 'One Band',
              album: 'One Album',
              trackNumber: i,
            ),
        ],
        reason: 'a name alone is never enough; this is one coherent album',
      );
    });

    test('folders with fewer than the minimum number of loose files', () {
      expectUntouched(
        mixedFolder('$root/Tiny', 4),
        reason: 'too few loose files to classify',
      );
    });

    test('the library root itself', () {
      expectUntouched(
        mixedFolder(root, 10),
        reason: 'the scan root is never a playlist',
      );
    });

    test('"car" keyword does not match inside words like "carnival"', () {
      expectUntouched(
        [
          for (var i = 0; i < 9; i++)
            song('$root/Carnival Recordings/$i.mp3'),
        ],
        reason: 'playlist words match on word boundaries only',
      );
    });
  });

  test('folders inside an explicit [PLAYLIST] folder are never classified',
      () {
    final result = classifier.classify(
      songs: spreadFolder('$root/[PLAYLIST] Gym/sub', 10,
          albums: 5, artists: 5),
      libraryRootPath: root,
      explicitPlaylistFolderPaths: {'$root/[PLAYLIST] Gym'},
    );

    expect(result.autoImports, isEmpty);
    expect(result.suggestions, isEmpty,
        reason: 'already a playlist — nothing to classify');
  });

  test('classification order is deterministic (path-sorted)', () {
    final songs = [
      ...mixedFolder('$root/Zulu Mixes', 6),
      ...mixedFolder('$root/Alpha Dump', 6),
      ...spreadFolder('$root/Big Gym', 10, albums: 5, artists: 5),
      ...spreadFolder('$root/Aa Workout', 10, albums: 5, artists: 5),
    ];

    final forward = classifier.classify(
      songs: songs,
      libraryRootPath: root,
    );
    final reversed = classifier.classify(
      songs: songs.reversed.toList(),
      libraryRootPath: root,
    );

    const expectedSuggestions = ['$root/Alpha Dump', '$root/Zulu Mixes'];
    const expectedAutoImports = ['$root/Aa Workout', '$root/Big Gym'];
    expect(forward.suggestions.map((s) => s.folderPath).toList(),
        expectedSuggestions);
    expect(reversed.suggestions.map((s) => s.folderPath).toList(),
        expectedSuggestions);
    expect(forward.autoImports.map((s) => s.folderPath).toList(),
        expectedAutoImports);
    expect(reversed.autoImports.map((s) => s.folderPath).toList(),
        expectedAutoImports);
  });
}
