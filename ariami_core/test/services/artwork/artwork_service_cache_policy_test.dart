import 'dart:io';

import 'package:ariami_core/models/artwork_size.dart';
import 'package:ariami_core/services/artwork/artwork_service.dart';
import 'package:test/test.dart';

void main() {
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
  });
}
