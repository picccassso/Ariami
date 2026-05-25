import 'dart:io';

import 'package:ariami_core/services/setup/music_folder_path_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('MusicFolderPathHelper.buildCandidatePaths', () {
    test('includes configured path and common locations in order', () {
      final candidates = MusicFolderPathHelper.buildCandidatePaths(
        configuredPath: '/srv/existing',
        username: 'pi',
        homeDirectory: '/home/pi',
      );

      expect(
        candidates,
        [
          '/srv/existing',
          '/home/pi/Music',
          '/media/pi',
          '/mnt',
          '/media',
          '/srv/music',
        ],
      );
    });

    test('deduplicates repeated candidates', () {
      final candidates = MusicFolderPathHelper.buildCandidatePaths(
        configuredPath: '/home/alex/Music',
        username: 'alex',
        homeDirectory: '/home/alex',
      );

      expect(candidates.first, '/home/alex/Music');
      expect(candidates.where((path) => path == '/home/alex/Music').length, 1);
    });
  });

  group('MusicFolderPathHelper.validate', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('ariami_music_folder_');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('returns empty error for blank path', () async {
      final result = await MusicFolderPathHelper.validate('   ');

      expect(result.isValid, isFalse);
      expect(result.error, MusicFolderPathError.empty);
    });

    test('returns missing for non-existent path', () async {
      final missingPath = p.join(tempRoot.path, 'missing');
      final result = await MusicFolderPathHelper.validate(missingPath);

      expect(result.isValid, isFalse);
      expect(result.exists, isFalse);
      expect(result.error, MusicFolderPathError.missing);
    });

    test('returns valid for readable directory', () async {
      final musicDir = Directory(p.join(tempRoot.path, 'music'));
      await musicDir.create(recursive: true);

      final result = await MusicFolderPathHelper.validate(musicDir.path);

      expect(result.isValid, isTrue);
      expect(result.exists, isTrue);
      expect(result.readable, isTrue);
      expect(result.error, isNull);
    });

    test('returns notDirectory for file path', () async {
      final file = File(p.join(tempRoot.path, 'track.mp3'));
      await file.writeAsString('test');

      final result = await MusicFolderPathHelper.validate(file.path);

      expect(result.isValid, isFalse);
      expect(result.exists, isTrue);
      expect(result.error, MusicFolderPathError.notDirectory);
    });
  });

  group('MusicFolderPathHelper.buildSuggestionPayload', () {
    test('returns validation payload for each candidate', () async {
      final tempRoot =
          await Directory.systemTemp.createTemp('ariami_music_suggestions_');
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final configured = Directory(p.join(tempRoot.path, 'library'));
      await configured.create(recursive: true);

      final payload = await MusicFolderPathHelper.buildSuggestionPayload(
        configuredPath: configured.path,
        username: 'tester',
        homeDirectory: p.join(tempRoot.path, 'home', 'tester'),
      );

      expect(payload, isNotEmpty);
      expect(payload.first['path'], configured.path);
      expect(payload.first['isValid'], isTrue);
      expect(payload.first['exists'], isTrue);
      expect(payload.first['readable'], isTrue);
    });
  });
}
