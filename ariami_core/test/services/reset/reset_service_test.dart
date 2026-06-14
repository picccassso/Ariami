import 'dart:io';

import 'package:ariami_core/services/reset/reset_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  const service = ResetService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ariami_reset_tests_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String path(String name) => p.join(tempDir.path, name);

  Future<File> createFile(String name) async {
    final file = File(path(name));
    await file.writeAsString('data');
    return file;
  }

  Future<Directory> createDir(String name) async {
    final dir = Directory(path(name));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'child.txt')).writeAsString('x');
    return dir;
  }

  test('deletes only the listed files and directories', () async {
    final keep = await createFile('keep.txt');
    final removeFile = await createFile('config.json');
    final removeDir = await createDir('artwork_cache');

    final result = await service.execute(ResetPlan(
      files: [removeFile.path],
      directories: [removeDir.path],
    ));

    expect(result.hasFailures, isFalse);
    expect(await removeFile.exists(), isFalse);
    expect(await removeDir.exists(), isFalse);
    // An unlisted sibling is untouched.
    expect(await keep.exists(), isTrue);
  });

  test('skips missing paths without failing', () async {
    final result = await service.execute(ResetPlan(
      files: [path('does_not_exist.json')],
    ));

    expect(result.hasFailures, isFalse);
    expect(
      result.entries.single.status,
      ResetEntryStatus.skippedMissing,
    );
  });

  group('music folder guard', () {
    test('blocks deleting the music folder itself', () async {
      final music = await createDir('Music');

      final result = await service.execute(ResetPlan(
        directories: [music.path],
        musicFolderPathGuard: music.path,
      ));

      expect(result.blocked, isNotEmpty);
      expect(await music.exists(), isTrue);
    });

    test('blocks deleting an ancestor of the music folder', () async {
      final music = await createDir('parent/Music');
      final ancestor = Directory(path('parent'));

      final result = await service.execute(ResetPlan(
        directories: [ancestor.path],
        musicFolderPathGuard: music.path,
      ));

      expect(result.blocked, isNotEmpty);
      expect(await ancestor.exists(), isTrue);
      expect(await music.exists(), isTrue);
    });

    test('blocks deleting a path inside the music folder', () async {
      final music = await createDir('Music');
      final inside = await createFile('Music/song.mp3');

      final result = await service.execute(ResetPlan(
        files: [inside.path],
        musicFolderPathGuard: music.path,
      ));

      expect(result.blocked, isNotEmpty);
      expect(await inside.exists(), isTrue);
    });

    test('allows deleting a sibling of the music folder', () async {
      final music = await createDir('Music');
      final cache = await createDir('artwork_cache');

      final result = await service.execute(ResetPlan(
        directories: [cache.path],
        musicFolderPathGuard: music.path,
      ));

      expect(result.hasFailures, isFalse);
      expect(result.blocked, isEmpty);
      expect(await cache.exists(), isFalse);
      expect(await music.exists(), isTrue);
    });
  });

  test('deletes a symlink without following it to the target', () async {
    final target = await createDir('real_target');
    final link = Link(path('link_to_target'));
    await link.create(target.path);

    final result = await service.execute(ResetPlan(
      directories: [link.path],
    ));

    expect(result.hasFailures, isFalse);
    // The link is gone but the target it pointed at is preserved.
    expect(await link.exists(), isFalse);
    expect(await target.exists(), isTrue);
    expect(await File(p.join(target.path, 'child.txt')).exists(), isTrue);
  }, onPlatform: {
    'windows': const Skip('Symlink creation requires elevation on Windows'),
  });
}
