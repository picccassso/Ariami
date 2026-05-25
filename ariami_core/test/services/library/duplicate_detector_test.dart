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

    test('does not merge songs with empty artist and different albums', () async {
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
  });
}
