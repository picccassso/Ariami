import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/metadata_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('MetadataCache atomic saves', () {
    late Directory tempDir;
    late File audioFile;
    late String cachePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_metadata_cache_');
      audioFile = File(p.join(tempDir.path, 'track.mp3'));
      await audioFile.writeAsBytes(<int>[1, 2, 3, 4]);
      cachePath = p.join(tempDir.path, 'metadata_cache.json');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('save writes through a temp file then replaces final cache', () async {
      final cache = MetadataCache(cachePath);
      await cache.put(
        audioFile.path,
        SongMetadata(filePath: audioFile.path, title: 'Track'),
      );

      expect(await cache.save(), isTrue);

      final cacheFile = File(cachePath);
      final tempFile = File('$cachePath.tmp');
      expect(await cacheFile.exists(), isTrue);
      expect(await tempFile.exists(), isFalse);

      final json =
          jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>;
      expect(json['version'], MetadataCache.schemaVersion);
      expect(
          (json['entries'] as Map<String, dynamic>), contains(audioFile.path));
    });

    test('upsert updates metadata for incremental changes', () async {
      final cache = MetadataCache(cachePath);
      await cache.put(
        audioFile.path,
        SongMetadata(filePath: audioFile.path, title: 'Original'),
      );

      await cache.upsert(
        audioFile.path,
        SongMetadata(
          filePath: audioFile.path,
          title: 'Updated',
          artist: 'Artist',
          duration: 200,
        ),
      );

      await cache.save();

      final reloaded = MetadataCache(cachePath);
      await reloaded.load();
      final metadata = await reloaded.get(audioFile.path);
      expect(metadata?.title, 'Updated');
      expect(metadata?.duration, 200);
    });

    test('remove deletes stale cache entry', () async {
      final cache = MetadataCache(cachePath);
      await cache.put(
        audioFile.path,
        SongMetadata(filePath: audioFile.path, title: 'Track'),
      );
      cache.remove(audioFile.path);
      expect(await cache.get(audioFile.path), isNull);
    });

    test('clean cache save skips rewriting existing file', () async {
      final cacheFile = File(cachePath);
      await cacheFile.writeAsString('existing');
      final originalModified = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now()
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch ~/
            1000 *
            1000,
      );
      await cacheFile.setLastModified(originalModified);

      final cache = MetadataCache(cachePath);
      expect(await cache.save(), isTrue);

      expect(await cacheFile.readAsString(), 'existing');
      expect((await cacheFile.stat()).modified, originalModified);
    });
  });
}
