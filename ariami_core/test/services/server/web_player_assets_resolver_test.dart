import 'dart:io';

import 'package:ariami_core/services/server/web_player_assets_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('WebPlayerAssetsResolver', () {
    const resolver = WebPlayerAssetsResolver();

    test('prefers ARIAMI_WEB_PLAYER_DIR over other candidates', () async {
      final resolution = await resolver.resolve(
        cwd: '/repo/ariami_cli',
        executableDir: '/opt/ariami/bin',
        scriptPath: '/repo/ariami_cli/bin/ariami_cli.dart',
        environment: {'ARIAMI_WEB_PLAYER_DIR': ' /custom/web_player '},
        exists: (path) =>
            path == '/custom/web_player' || path == '/opt/ariami/bin/web_player',
      );

      expect(resolution.found, isTrue);
      expect(resolution.path, '/custom/web_player');
      expect(resolution.candidatesChecked.first, '/custom/web_player');
    });

    test('checks candidates in documented order across release and dev layouts',
        () async {
      final checks = <String>[];
      final resolution = await resolver.resolve(
        cwd: '/workspace/ariami_cli',
        executableDir: '/opt/Ariami.app/Contents/MacOS',
        scriptPath: '/workspace/ariami_cli/bin/ariami_cli.dart',
        environment: const {'ARIAMI_WEB_PLAYER_DIR': '   '},
        exists: (path) {
          checks.add(path);
          return false;
        },
      );

      expect(resolution.found, isFalse);
      expect(resolution.path, isNull);
      expect(checks, [
        '/opt/Ariami.app/Contents/MacOS/web_player',
        '/opt/Ariami.app/Contents/web_player',
        '/opt/Ariami.app/Contents/Resources/web_player',
        '/workspace/ariami_cli/web_player',
        '/workspace/ariami_web/build/web',
        '/workspace/ariami_cli/ariami_web/build/web',
        '/workspace/ariami_web/build/web',
        '/workspace/ariami_cli/web_player',
      ]);
    });

    test('verifies index.html existence by default', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('ariami_web_player_resolver_');
      try {
        final emptyDir = Directory(p.join(tempDir.path, 'empty', 'web_player'))
          ..createSync(recursive: true);
        final populatedDir =
            Directory(p.join(tempDir.path, 'app', 'Resources', 'web_player'))
              ..createSync(recursive: true);
        File(p.join(populatedDir.path, 'index.html')).writeAsStringSync('<html>');

        final resolution = await resolver.resolve(
          cwd: emptyDir.parent.path,
          executableDir: p.join(tempDir.path, 'app', 'MacOS'),
          scriptPath: '',
          environment: const {},
        );

        expect(resolution.found, isTrue);
        expect(resolution.path, populatedDir.path);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
