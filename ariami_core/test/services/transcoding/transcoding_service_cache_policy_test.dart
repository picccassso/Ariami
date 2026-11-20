import 'dart:io';

import 'package:ariami_core/models/quality_preset.dart';
import 'package:ariami_core/services/transcoding/transcoding_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _TestTranscodingService extends TranscodingService {
  _TestTranscodingService({
    required super.cacheDirectory,
    super.maxCacheSizeMB,
  });

  final List<(QualityPreset, TranscodeOutputFormat)> transcodeCalls = [];
  int outputSizeBytes = 64;

  @override
  Future<bool> isSonicAvailable() async => true;

  @override
  Future<File?> runTranscode(
    String sourcePath,
    String outputPath,
    QualityPreset quality, {
    TranscodeOutputFormat outputFormat = TranscodeOutputFormat.aac,
  }) async {
    transcodeCalls.add((quality, outputFormat));
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      List<int>.filled(outputSizeBytes, outputFormat.index + 1),
    );
    return file;
  }
}

void main() {
  group('TranscodingService cache policy', () {
    late Directory tempDir;
    late _TestTranscodingService service;
    late File sourceFile;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('ariami_transcoding_cache_');
      service = _TestTranscodingService(cacheDirectory: tempDir.path);
      sourceFile = File(p.join(tempDir.path, 'source.mp3'));
      await sourceFile.writeAsBytes(List<int>.filled(128, 7));
    });

    tearDown(() async {
      service.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('invalidateSong removes completed and partial aac/m4a outputs',
        () async {
      final lowDir = Directory(p.join(tempDir.path, 'low'))..createSync();
      final highDir = Directory(p.join(tempDir.path, 'high'))..createSync();

      final lowAac = File(p.join(lowDir.path, 'song-1.aac'))
        ..writeAsBytesSync(<int>[1, 2, 3]);
      final lowAacPartial = File('${lowAac.path}.partial')
        ..writeAsBytesSync(<int>[4]);
      final lowM4a = File(p.join(lowDir.path, 'song-1.m4a'))
        ..writeAsBytesSync(<int>[5, 6]);
      final highM4a = File(p.join(highDir.path, 'song-1.m4a'))
        ..writeAsBytesSync(<int>[7, 8]);
      final highM4aPartial = File('${highM4a.path}.partial')
        ..writeAsBytesSync(<int>[9]);

      await service.invalidateSong('song-1');

      expect(await lowAac.exists(), isFalse);
      expect(await lowAacPartial.exists(), isFalse);
      expect(await lowM4a.exists(), isFalse);
      expect(await highM4a.exists(), isFalse);
      expect(await highM4aPartial.exists(), isFalse);
    });

    test('high+m4a bypasses bitrate fast-path and keeps distinct cache keys',
        () async {
      final highM4a = await service.getTranscodedFile(
        sourceFile.path,
        'song-1',
        QualityPreset.high,
        outputFormat: TranscodeOutputFormat.m4a,
        sourceBitrateKbps: 128,
      );
      expect(highM4a, isNotNull);
      expect(highM4a!.path, p.join(tempDir.path, 'high', 'song-1.m4a'));
      expect(
        service.transcodeCalls,
        [(QualityPreset.high, TranscodeOutputFormat.m4a)],
      );

      final skippedMedM4a = await service.getTranscodedFile(
        sourceFile.path,
        'song-1',
        QualityPreset.medium,
        outputFormat: TranscodeOutputFormat.m4a,
        sourceBitrateKbps: 128,
      );
      expect(skippedMedM4a, isNull);

      final medAac = await service.getTranscodedFile(
        sourceFile.path,
        'song-1',
        QualityPreset.medium,
        outputFormat: TranscodeOutputFormat.aac,
        sourceBitrateKbps: 320,
      );
      final medM4a = await service.getTranscodedFile(
        sourceFile.path,
        'song-1',
        QualityPreset.medium,
        outputFormat: TranscodeOutputFormat.m4a,
        sourceBitrateKbps: 320,
      );
      expect(medAac!.path, p.join(tempDir.path, 'medium', 'song-1.aac'));
      expect(medM4a!.path, p.join(tempDir.path, 'medium', 'song-1.m4a'));

      // Rebuilding index from disk keeps both .aac and .m4a entries distinct.
      service.dispose();
      final rebuilt = _TestTranscodingService(cacheDirectory: tempDir.path);
      try {
        expect(await rebuilt.getCacheSize(), 192);
      } finally {
        rebuilt.dispose();
      }
    });

    test('markInUse protects m4a cache entry from LRU eviction', () async {
      service.dispose();
      service = _TestTranscodingService(
        cacheDirectory: tempDir.path,
        maxCacheSizeMB: 1,
      );

      final highM4a = await service.getTranscodedFile(
        sourceFile.path,
        'song-in-use',
        QualityPreset.high,
        outputFormat: TranscodeOutputFormat.m4a,
      );
      expect(highM4a, isNotNull);
      service.markInUse(
        'song-in-use',
        QualityPreset.high,
        outputFormat: TranscodeOutputFormat.m4a,
      );

      service.outputSizeBytes = 1024 * 1024;
      final otherM4a = await service.getTranscodedFile(
        sourceFile.path,
        'song-evictable',
        QualityPreset.high,
        outputFormat: TranscodeOutputFormat.m4a,
      );
      expect(otherM4a, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await highM4a!.exists(), isTrue);
      expect(await otherM4a!.exists(), isFalse);
      service.releaseInUse(
        'song-in-use',
        QualityPreset.high,
        outputFormat: TranscodeOutputFormat.m4a,
      );
    });
  });
}
