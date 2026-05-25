import 'dart:io';

import 'package:ariami_cli/models/music_folder_validation_result.dart';
import 'package:ariami_core/services/setup/music_folder_path_helper.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MusicFolderValidationResult.fromJson', () {
    test('parses validate endpoint payload', () {
      final result = MusicFolderValidationResult.fromJson({
        'success': false,
        'validation': {
          'path': '/missing',
          'exists': false,
          'readable': false,
          'error': 'missing',
          'message': 'Path does not exist on the server',
          'isValid': false,
        },
      });

      expect(result.isValid, isFalse);
      expect(result.path, '/missing');
      expect(result.error, 'missing');
    });

    test('parses suggestion payload', () {
      final result = MusicFolderValidationResult.fromJson({
        'path': '/home/user/Music',
        'exists': true,
        'readable': true,
        'isValid': true,
        'message': 'Folder is accessible',
      });

      expect(result.isValid, isTrue);
      expect(result.path, '/home/user/Music');
    });
  });

  group('MusicFolderPathHelper suggestions', () {
    test('includes home Music path for current environment', () async {
      final home = Platform.environment['HOME'];
      if (home == null) {
        return;
      }

      final candidates = MusicFolderPathHelper.buildCandidatePaths(
        homeDirectory: home,
        username: Platform.environment['USER'],
      );

      expect(candidates, contains(p.join(home, 'Music')));
    });
  });
}
