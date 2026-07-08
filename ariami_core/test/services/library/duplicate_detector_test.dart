import 'dart:io';

import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/duplicate_detector.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

SongMetadata _song({
  required String path,
  String? title,
  String? artist,
  String? album,
  int? duration,
  int? fileSize,
}) {
  return SongMetadata(
    filePath: path,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    fileSize: fileSize,
  );
}

void main() {
  group('DuplicateDetector metadata matching', () {
    final detector = DuplicateDetector();

    test('does not merge songs with empty artist and different albums',
        () async {
      final songs = [
        _song(
          path: '/a.mp3',
          title: 'Same Title',
          album: 'Album A',
          duration: 180,
        ),
        _song(
          path: '/b.mp3',
          title: 'Same Title',
          album: 'Album B',
          duration: 180,
        ),
      ];

      final groups = await detector.detectDuplicates(
        songs,
        useHashMatching: false,
      );

      expect(groups, isEmpty);
    });

    test('merges when title and artist match with similar duration', () async {
      final songs = [
        _song(
          path: '/a.mp3',
          title: 'Song',
          artist: 'Artist',
          duration: 180,
        ),
        _song(
          path: '/b.mp3',
          title: 'Song',
          artist: 'Artist',
          duration: 181,
        ),
      ];

      final groups = await detector.detectDuplicates(
        songs,
        useHashMatching: false,
      );

      expect(groups, hasLength(1));
      expect(groups.first.duplicates, hasLength(1));
    });

    test('does not merge matching tracks from different albums', () async {
      final songs = [
        _song(
          path: '/base/song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          duration: 180,
        ),
        _song(
          path: '/deluxe/song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Album - Deluxe',
          duration: 180,
        ),
      ];

      final groups = await detector.detectDuplicates(
        songs,
        useHashMatching: false,
      );

      expect(groups, isEmpty);
    });

    test('keeps preferred album path over playlist copy', () async {
      final songs = [
        _song(
          path: '/music/album/song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          duration: 180,
          fileSize: 100,
        ),
        _song(
          path: '/music/[PLAYLIST] Mix/song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          duration: 180,
          fileSize: 200,
        ),
      ];

      final groups = await detector.detectDuplicates(
        songs,
        useHashMatching: false,
        preferredPaths: {'/music/album/song.mp3'},
      );

      expect(groups, hasLength(1));
      expect(groups.first.original.filePath, '/music/album/song.mp3');
      expect(
        groups.first.duplicates.single.filePath,
        '/music/[PLAYLIST] Mix/song.mp3',
      );
    });

    test('merges playlist copy with a different embedded album tag', () async {
      final songs = [
        _song(
          path: '/music/album/song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Canonical Album',
          duration: 180,
          fileSize: 100,
        ),
        _song(
          path: '/music/[PLAYLIST] Mix/song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Playlist Export',
          duration: 180,
          fileSize: 200,
        ),
      ];

      final groups = await detector.detectDuplicates(
        songs,
        useHashMatching: false,
        preferredPaths: {'/music/album/song.mp3'},
      );

      expect(groups, hasLength(1));
      expect(groups.first.original.filePath, '/music/album/song.mp3');
      expect(
        groups.first.duplicates.single.filePath,
        '/music/[PLAYLIST] Mix/song.mp3',
      );
    });

    test('playlist copy cannot bridge tracks from distinct albums', () async {
      final songs = [
        _song(
          path: '/music/[PLAYLIST] Mix/song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Playlist Export',
          duration: 180,
          fileSize: 300,
        ),
        _song(
          path: '/music/base/song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          duration: 180,
          fileSize: 100,
        ),
        _song(
          path: '/music/deluxe/song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Album - Deluxe',
          duration: 180,
          fileSize: 200,
        ),
      ];
      final preferredPaths = {
        '/music/base/song.mp3',
        '/music/deluxe/song.mp3',
      };

      final groups = await detector.detectDuplicates(
        songs,
        useHashMatching: false,
        preferredPaths: preferredPaths,
      );
      final uniqueSongs = detector.filterDuplicates(songs, groups);

      expect(groups, hasLength(1));
      expect(
        uniqueSongs.map((song) => song.filePath),
        containsAll(preferredPaths),
      );
      expect(
        uniqueSongs.map((song) => song.filePath),
        isNot(contains('/music/[PLAYLIST] Mix/song.mp3')),
      );
    });

    test('merges empty-artist songs with same album and duration', () async {
      final songs = [
        _song(
          path: '/a.mp3',
          title: 'Instrumental',
          album: 'Shared Album',
          duration: 200,
        ),
        _song(
          path: '/b.mp3',
          title: 'Instrumental',
          album: 'Shared Album',
          duration: 201,
        ),
      ];

      final groups = await detector.detectDuplicates(
        songs,
        useHashMatching: false,
      );

      expect(groups, hasLength(1));
    });

    test('does not merge empty-artist songs when duration differs', () async {
      final songs = [
        _song(
          path: '/a.mp3',
          title: 'Instrumental',
          album: 'Shared Album',
          duration: 200,
        ),
        _song(
          path: '/b.mp3',
          title: 'Instrumental',
          album: 'Shared Album',
          duration: 240,
        ),
      ];

      final groups = await detector.detectDuplicates(
        songs,
        useHashMatching: false,
      );

      expect(groups, isEmpty);
    });
  });

  group('DuplicateDetector partial hash confirmation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_dup_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('does not treat same-size different-content files as duplicates',
        () async {
      final fileA = File('${tempDir.path}/a.bin');
      final fileB = File('${tempDir.path}/b.bin');
      await fileA.writeAsBytes(List<int>.filled(200000, 1));
      await fileB.writeAsBytes(List<int>.filled(200000, 2));

      final size = await fileA.length();
      final songs = [
        _song(path: fileA.path, title: 'A', artist: 'X', fileSize: size),
        _song(path: fileB.path, title: 'B', artist: 'Y', fileSize: size),
      ];

      final detector = DuplicateDetector();
      final groups = await detector.detectDuplicates(
        songs,
        useMetadataMatching: false,
      );

      expect(groups, isEmpty);
    });

    test('confirms identical files via full hash', () async {
      final bytes = List<int>.filled(200000, 7);
      final fileA = File('${tempDir.path}/same-a.bin');
      final fileB = File('${tempDir.path}/same-b.bin');
      await fileA.writeAsBytes(bytes);
      await fileB.writeAsBytes(bytes);

      final size = await fileA.length();
      final songs = [
        _song(path: fileA.path, title: 'A', artist: 'X', fileSize: size),
        _song(path: fileB.path, title: 'B', artist: 'Y', fileSize: size),
      ];

      final detector = DuplicateDetector();
      final groups = await detector.detectDuplicates(
        songs,
        useMetadataMatching: false,
      );

      expect(groups, hasLength(1));
      expect(groups.first.matchType.name, 'exactHash');
      expect(md5.convert(bytes).toString(), isNotEmpty);
    });

    test('dedupes multiple distinct pairs sharing one partial-hash bucket',
        () async {
      // All four files share size + first/last 64KB (identical partial hash)
      // but form two distinct identical pairs differing in the middle bytes.
      List<int> buildBytes(int middleByte) {
        final bytes = List<int>.filled(200000, 0);
        for (var i = 65536; i < 134464; i++) {
          bytes[i] = middleByte;
        }
        return bytes;
      }

      final pairABytes = buildBytes(1);
      final pairBBytes = buildBytes(2);

      final fileA1 = File('${tempDir.path}/pair-a1.bin');
      final fileA2 = File('${tempDir.path}/pair-a2.bin');
      final fileB1 = File('${tempDir.path}/pair-b1.bin');
      final fileB2 = File('${tempDir.path}/pair-b2.bin');
      await fileA1.writeAsBytes(pairABytes);
      await fileA2.writeAsBytes(pairABytes);
      await fileB1.writeAsBytes(pairBBytes);
      await fileB2.writeAsBytes(pairBBytes);

      final size = await fileA1.length();
      final songs = [
        _song(path: fileA1.path, title: 'A1', artist: 'X', fileSize: size),
        _song(path: fileA2.path, title: 'A2', artist: 'X', fileSize: size),
        _song(path: fileB1.path, title: 'B1', artist: 'Y', fileSize: size),
        _song(path: fileB2.path, title: 'B2', artist: 'Y', fileSize: size),
      ];

      final detector = DuplicateDetector();
      final groups = await detector.detectDuplicates(
        songs,
        useMetadataMatching: false,
      );

      expect(groups, hasLength(2));
      final groupedPaths = groups
          .map((g) => {g.original.filePath, ...g.duplicates.map((d) => d.filePath)})
          .toList();
      expect(groupedPaths, contains(equals({fileA1.path, fileA2.path})));
      expect(groupedPaths, contains(equals({fileB1.path, fileB2.path})));
    });

    test(
        'the surviving original is deterministic when duplicates tie on '
        'quality, regardless of input order', () async {
      // Byte-identical copies with equal metadata tie every quality
      // criterion; the survivor must not depend on directory traversal
      // order (it varies by filesystem — this failed on ext4 CI while
      // passing on APFS) because the survivor's path becomes the song ID.
      final identicalBytes = List<int>.filled(4096, 12);
      final canonical = File('${tempDir.path}/Album/one.mp3');
      final copy = File('${tempDir.path}/Copies/one-copy.mp3');
      for (final file in [canonical, copy]) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(identicalBytes);
      }

      final size = await canonical.length();
      SongMetadata songFor(File file) => _song(
            path: file.path,
            title: 'One',
            artist: 'A',
            album: 'X',
            fileSize: size,
          );

      for (final songs in [
        [songFor(canonical), songFor(copy)],
        [songFor(copy), songFor(canonical)],
      ]) {
        final groups = await DuplicateDetector().detectDuplicates(
          songs,
          useMetadataMatching: false,
        );

        expect(groups, hasLength(1));
        expect(
          groups.single.original.filePath,
          canonical.path,
          reason: 'ties break to the lexicographically first path, '
              'independent of input order',
        );
      }
    });
  });
}
