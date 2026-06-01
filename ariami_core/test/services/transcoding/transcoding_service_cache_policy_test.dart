import 'dart:io';

import 'package:ariami_core/services/transcoding/transcoding_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('TranscodingService cache policy', () {
    late Directory tempDir;
    late TranscodingService service;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('ariami_transcoding_cache_');
      service = TranscodingService(cacheDirectory: tempDir.path);
    });

    tearDown(() async {
      service.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('invalidateSong removes completed and partial cached output',
        () async {
      final lowQualityDir = Directory(p.join(tempDir.path, 'low'));
      await lowQualityDir.create(recursive: true);

      final cachedFile = File(p.join(lowQualityDir.path, 'song-1.aac'));
      final partialFile = File('${cachedFile.path}.partial');
      await cachedFile.writeAsBytes(<int>[1, 2, 3]);
      await partialFile.writeAsBytes(<int>[4, 5, 6]);

      await service.invalidateSong('song-1');

      expect(await cachedFile.exists(), isFalse);
      expect(await partialFile.exists(), isFalse);
    });
  });
}
