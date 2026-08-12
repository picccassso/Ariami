import 'dart:io';
import 'dart:convert';

import 'package:ariami_core/models/artwork_size.dart';
import 'package:ariami_core/services/artwork/artwork_service.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  final validJpeg = base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBxAQEBAQEBAPEA8PDw8QDw8QDw8PDw8PFREWFhURFRUYHSggGBolGxUVITEhJSkrLi4uFx8zODMtNygtLisBCgoKDQ0NDg0NDisZFRkrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrK//AABEIABQAFAMBIgACEQEDEQH/xAAXAAADAQAAAAAAAAAAAAAAAAAAAQID/8QAFhABAQEAAAAAAAAAAAAAAAAAAQAC/8QAFQEBAQAAAAAAAAAAAAAAAAAAAwX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCfAAH/2Q==',
  );

  group('ArtworkService cache write policy', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_artwork_policy_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('can serve cached artwork without touching mtime', () async {
      final cachedFile = File('${tempDir.path}/thumbnail/album-1.jpg');
      await cachedFile.parent.create(recursive: true);
      await cachedFile.writeAsBytes(<int>[1, 2, 3]);
      await File('${cachedFile.path}.source-md5')
          .writeAsString(md5.convert(<int>[9, 9, 9]).toString());
      final originalModified = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now()
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch ~/
            1000 *
            1000,
      );
      await cachedFile.setLastModified(originalModified);

      final service = ArtworkService(
        cacheDirectory: tempDir.path,
        touchOnCacheHit: false,
      );

      final bytes = await service.getArtwork(
        'album-1',
        <int>[9, 9, 9],
        ArtworkSize.thumbnail,
      );

      expect(bytes, <int>[1, 2, 3]);
      expect((await cachedFile.stat()).modified, originalModified);
    });

    test('throttles cache-hit mtime updates', () async {
      final cachedFile = File('${tempDir.path}/thumbnail/album-2.jpg');
      await cachedFile.parent.create(recursive: true);
      await cachedFile.writeAsBytes(<int>[4, 5, 6]);
      await File('${cachedFile.path}.source-md5')
          .writeAsString(md5.convert(<int>[9, 9, 9]).toString());
      final recentModified = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now()
                .subtract(const Duration(minutes: 5))
                .millisecondsSinceEpoch ~/
            1000 *
            1000,
      );
      await cachedFile.setLastModified(recentModified);

      final service = ArtworkService(
        cacheDirectory: tempDir.path,
        touchThrottle: const Duration(minutes: 30),
      );

      await service.getArtwork(
        'album-2',
        <int>[9, 9, 9],
        ArtworkSize.thumbnail,
      );

      expect((await cachedFile.stat()).modified, recentModified);
    });

    test('does not serve a legacy thumbnail with unknown source artwork',
        () async {
      final cachedFile = File('${tempDir.path}/thumbnail/song-1.jpg');
      await cachedFile.parent.create(recursive: true);
      await cachedFile.writeAsBytes(<int>[1, 2, 3]);

      final service = ArtworkService(cacheDirectory: tempDir.path);
      final bytes = await service.getArtwork(
        'song-1',
        validJpeg,
        ArtworkSize.thumbnail,
      );

      expect(bytes, isNot(<int>[1, 2, 3]));
      expect(await File('${cachedFile.path}.source-md5').readAsString(),
          md5.convert(validJpeg).toString());
    });

    test('does not serve a thumbnail derived from different source artwork',
        () async {
      final cachedFile = File('${tempDir.path}/thumbnail/song-2.jpg');
      await cachedFile.parent.create(recursive: true);
      await cachedFile.writeAsBytes(<int>[4, 5, 6]);
      await File('${cachedFile.path}.source-md5')
          .writeAsString(md5.convert(<int>[8, 8, 8]).toString());

      final service = ArtworkService(cacheDirectory: tempDir.path);
      final bytes = await service.getArtwork(
        'song-2',
        validJpeg,
        ArtworkSize.thumbnail,
      );

      expect(bytes, isNot(<int>[4, 5, 6]));
      expect(await File('${cachedFile.path}.source-md5').readAsString(),
          md5.convert(validJpeg).toString());
    });
  });
}
