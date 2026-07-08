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

  /// N loose files in [folder], each from its own album/artist, with the
  /// original (duplicated across folder members? no — distinct) tags.
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

  group('suggests', () {
    test('a mixed folder with many albums and artists', () {
      final suggestions = classifier.detectSuggestions(
        songs: mixedFolder('$root/Old iPod Dump', 8),
        libraryRootPath: root,
      );

      expect(suggestions, hasLength(1));
      final s = suggestions.single;
      expect(s.folderPath, '$root/Old iPod Dump');
      expect(s.name, 'Old iPod Dump');
      expect(s.songCount, 8);
      expect(s.albumCount, 8);
      expect(s.artistCount, 8);
      expect(s.missingTags, isFalse);
      expect(s.reasons, isNotEmpty);
    });

    test('a Road Trip style folder with many album tags', () {
      final suggestions = classifier.detectSuggestions(
        songs: mixedFolder('$root/Road Trip', 6),
        libraryRootPath: root,
      );

      expect(suggestions, hasLength(1));
      expect(suggestions.single.name, 'Road Trip');
      expect(
        suggestions.single.reasons,
        contains('folder name looks like a playlist'),
      );
    });

    test('a missing-tag folder ONLY when its name is playlist-like, flagged',
        () {
      List<SongMetadata> untagged(String folder) => [
            for (var i = 0; i < 6; i++) song('$folder/track$i.mp3'),
          ];

      final playlistLike = classifier.detectSuggestions(
        songs: untagged('$root/Gym Mix'),
        libraryRootPath: root,
      );
      expect(playlistLike, hasLength(1));
      expect(playlistLike.single.missingTags, isTrue);
      expect(
        playlistLike.single.reasons.join(' '),
        contains('review before importing'),
      );

      final anonymous = classifier.detectSuggestions(
        songs: untagged('$root/New Folder'),
        libraryRootPath: root,
      );
      expect(anonymous, isEmpty,
          reason: 'untagged folders without a playlist-like name are left '
              'alone');
    });
  });

  group('never suggests', () {
    test('a normal album folder', () {
      final suggestions = classifier.detectSuggestions(
        songs: [
          for (var i = 1; i <= 10; i++)
            song(
              '$root/Arctic Monkeys/AM/$i.mp3',
              title: 'Song $i',
              artist: 'Arctic Monkeys',
              album: 'AM',
              trackNumber: i,
            ),
        ],
        libraryRootPath: root,
      );

      expect(suggestions, isEmpty);
    });

    test('a compilation album despite many track artists', () {
      final suggestions = classifier.detectSuggestions(
        songs: [
          for (var i = 1; i <= 12; i++)
            song(
              '$root/NOW 100/$i.mp3',
              title: 'Hit $i',
              artist: 'Pop Artist $i',
              albumArtist: 'Various Artists',
              album: 'NOW 100',
              trackNumber: i,
            ),
        ],
        libraryRootPath: root,
      );

      expect(suggestions, isEmpty,
          reason: 'Various Artists compilations are protected');
    });

    test('a compilation spread over several albums', () {
      final suggestions = classifier.detectSuggestions(
        songs: [
          for (var i = 0; i < 8; i++)
            song(
              '$root/Charts/$i.mp3',
              title: 'Hit $i',
              artist: 'Artist $i',
              albumArtist: 'Various Artists',
              album: 'NOW ${90 + i}',
            ),
        ],
        libraryRootPath: root,
      );

      expect(suggestions, isEmpty);
    });

    test('an artist dump dominated by one album artist', () {
      final suggestions = classifier.detectSuggestions(
        songs: [
          for (var i = 0; i < 8; i++)
            song(
              '$root/Metallica Everything/$i.mp3',
              title: 'Song $i',
              artist: 'Metallica',
              albumArtist: 'Metallica',
              album: 'Album ${i % 5}',
            ),
        ],
        libraryRootPath: root,
      );

      expect(suggestions, isEmpty,
          reason: 'a single dominant album artist means an artist folder, '
              'not a playlist');
    });

    test('a folder just because it has a playlist-like name', () {
      final suggestions = classifier.detectSuggestions(
        songs: [
          for (var i = 1; i <= 6; i++)
            song(
              '$root/Party/$i.mp3',
              title: 'Song $i',
              artist: 'One Band',
              album: 'One Album',
              trackNumber: i,
            ),
        ],
        libraryRootPath: root,
      );

      expect(suggestions, isEmpty,
          reason: 'a name alone is never enough; this is one coherent album');
    });

    test('folders with fewer than the minimum number of loose files', () {
      final suggestions = classifier.detectSuggestions(
        songs: mixedFolder('$root/Tiny', 4),
        libraryRootPath: root,
      );

      expect(suggestions, isEmpty);
    });

    test('the library root itself', () {
      final suggestions = classifier.detectSuggestions(
        songs: mixedFolder(root, 10),
        libraryRootPath: root,
      );

      expect(suggestions, isEmpty);
    });

    test('folders inside an explicit [PLAYLIST] folder', () {
      final suggestions = classifier.detectSuggestions(
        songs: mixedFolder('$root/[PLAYLIST] Gym/sub', 8),
        libraryRootPath: root,
        explicitPlaylistFolderPaths: {'$root/[PLAYLIST] Gym'},
      );

      expect(suggestions, isEmpty,
          reason: 'already a playlist — nothing to suggest');
    });

    test('"car" keyword does not match inside words like "carnival"', () {
      final suggestions = classifier.detectSuggestions(
        songs: [
          for (var i = 0; i < 6; i++)
            song('$root/Carnival Recordings/$i.mp3'),
        ],
        libraryRootPath: root,
      );

      expect(suggestions, isEmpty);
    });
  });

  test('suggestion order is deterministic (path-sorted)', () {
    final songs = [
      ...mixedFolder('$root/Zulu Mixes', 6),
      ...mixedFolder('$root/Alpha Dump', 6),
      ...mixedFolder('$root/Mid Collection', 6),
    ];

    final forward = classifier.detectSuggestions(
      songs: songs,
      libraryRootPath: root,
    );
    final reversed = classifier.detectSuggestions(
      songs: songs.reversed.toList(),
      libraryRootPath: root,
    );

    final expectedOrder = [
      '$root/Alpha Dump',
      '$root/Mid Collection',
      '$root/Zulu Mixes',
    ];
    expect(forward.map((s) => s.folderPath).toList(), expectedOrder);
    expect(reversed.map((s) => s.folderPath).toList(), expectedOrder);
  });
}
