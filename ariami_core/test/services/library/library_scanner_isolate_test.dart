import 'dart:io';

import 'package:ariami_core/services/library/library_scanner_isolate.dart';
import 'package:test/test.dart';

void main() {
  group('LibraryScannerIsolate resilience', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_scan_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        // Restore permissions on any directories locked by tests so cleanup works.
        await Process.run('chmod', ['-R', 'u+rwx', tempDir.path]);
        await tempDir.delete(recursive: true);
      }
    });

    Future<File> writeFakeAudio(String relativePath, List<int> bytes) async {
      final file = File('${tempDir.path}/$relativePath');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file;
    }

    test('an unreadable subdirectory skips only that subtree', () async {
      await writeFakeAudio('readable/song-one.mp3', List<int>.filled(4096, 1));
      await writeFakeAudio('readable/song-two.mp3', List<int>.filled(4096, 2));
      await writeFakeAudio('locked/hidden-song.mp3', List<int>.filled(4096, 3));

      final lockedDir = Directory('${tempDir.path}/locked');
      await Process.run('chmod', ['000', lockedDir.path]);

      final result = await LibraryScannerIsolate.scan(tempDir.path);

      expect(result.library, isNotNull,
          reason: 'scan must survive an unreadable directory');
      expect(result.library!.totalSongs, equals(2));
      expect(
        result.scanDiagnostics.failedFiles
            .any((f) => f.path == lockedDir.path),
        isTrue,
        reason: 'unreadable directory should appear in scan diagnostics',
      );
    }, skip: Platform.isWindows ? 'requires POSIX permissions' : false);

    test('scans a library that lives under a dotted directory', () async {
      final hiddenRoot = Directory('${tempDir.path}/.local/music');
      await hiddenRoot.create(recursive: true);
      await File('${hiddenRoot.path}/track.mp3')
          .writeAsBytes(List<int>.filled(4096, 4));

      final result = await LibraryScannerIsolate.scan(hiddenRoot.path);

      expect(result.library, isNotNull);
      expect(result.library!.totalSongs, equals(1));
    });

    test('still skips hidden entries below the scan root', () async {
      await writeFakeAudio('visible.mp3', List<int>.filled(4096, 5));
      await writeFakeAudio('.hidden-dir/skipped.mp3', List<int>.filled(4096, 6));
      await writeFakeAudio('._resource-fork.mp3', List<int>.filled(4096, 7));

      final result = await LibraryScannerIsolate.scan(tempDir.path);

      expect(result.library, isNotNull);
      expect(result.library!.totalSongs, equals(1));
    });

    test('preserves duplicate-detection hashes across cached rescans',
        () async {
      // Two identical files force partial-hash computation on the first scan.
      final bytes = List<int>.filled(4096, 8);
      await writeFakeAudio('copy-a.mp3', bytes);
      await writeFakeAudio('copy-b.mp3', bytes);

      final firstScan = await LibraryScannerIsolate.scan(tempDir.path);
      expect(firstScan.updatedCache, isNotNull);
      final hashedPaths = firstScan.updatedCache!.entries
          .where((e) => e.value['partialHash'] != null)
          .map((e) => e.key)
          .toSet();
      expect(hashedPaths, isNotEmpty,
          reason: 'first scan should compute and store partial hashes');

      // Cache entries are only trusted when they already carry a duration;
      // the junk fixtures have none, so patch one in (as a real scan of valid
      // audio would have).
      final cacheData = firstScan.updatedCache!;
      for (final entry in cacheData.values) {
        (entry['metadata'] as Map<String, dynamic>)['duration'] = 180;
      }

      // Second scan runs fully from cache; the hashes must survive it.
      final secondScan = await LibraryScannerIsolate.scan(
        tempDir.path,
        cacheData: cacheData,
      );
      expect(secondScan.cacheHits, greaterThan(0));
      final preservedPaths = secondScan.updatedCache!.entries
          .where((e) => e.value['partialHash'] != null)
          .map((e) => e.key)
          .toSet();
      expect(preservedPaths, containsAll(hashedPaths),
          reason: 'cached rescan must not drop previously computed hashes');
    });
  });
}
