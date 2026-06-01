import 'package:ariami_cli/services/web_assets_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebAssetsResolver', () {
    final resolver = WebAssetsResolver();

    test('prefers cwd build/web over other candidates', () async {
      final resolution = await resolver.resolve(
        cwd: '/project',
        executableDir: '/opt/ariami',
        scriptPath: '/project/bin/ariami_cli.dart',
        exists: (path) => path == '/project/build/web',
      );

      expect(resolution.found, isTrue);
      expect(resolution.path, '/project/build/web');
      expect(
        resolution.candidatesChecked.first,
        '/project/build/web',
      );
    });

    test('falls back to executable web directory', () async {
      final resolution = await resolver.resolve(
        cwd: '/tmp',
        executableDir: '/opt/ariami',
        scriptPath: '/opt/ariami/bin/ariami_cli.dart',
        exists: (path) => path == '/opt/ariami/web',
      );

      expect(resolution.found, isTrue);
      expect(resolution.path, '/opt/ariami/web');
    });

    test('finds sibling web directory for bundled bin executable', () async {
      final resolution = await resolver.resolve(
        cwd: '/opt/ariami/bin',
        executableDir: '/opt/ariami/bin',
        scriptPath: '/opt/ariami/bin/ariami_cli',
        exists: (path) => path == '/opt/ariami/web',
      );

      expect(resolution.found, isTrue);
      expect(resolution.path, '/opt/ariami/web');
    });

    test('uses script package root fallback for dart run layouts', () async {
      final resolution = await resolver.resolve(
        cwd: '/tmp',
        executableDir: '/usr/lib/dart/bin',
        scriptPath: '/home/user/ariami_cli/bin/ariami_cli.dart',
        exists: (path) => path == '/home/user/ariami_cli/web',
      );

      expect(resolution.found, isTrue);
      expect(resolution.path, '/home/user/ariami_cli/web');
      expect(
        resolution.candidatesChecked,
        contains('/home/user/ariami_cli/web'),
      );
    });

    test('returns checked candidates when nothing exists', () async {
      final resolution = await resolver.resolve(
        cwd: '/project',
        executableDir: '/opt/ariami',
        scriptPath: '/project/bin/ariami_cli.dart',
        exists: (_) => false,
      );

      expect(resolution.found, isFalse);
      expect(resolution.path, isNull);
      expect(resolution.cwd, '/project');
      expect(resolution.executableDir, '/opt/ariami');
      expect(resolution.candidatesChecked.length, 8);
    });

    test('isDevRun detects dart script invocations', () {
      expect(
        resolver.isDevRun(scriptPath: '/project/bin/ariami_cli.dart'),
        isTrue,
      );
      expect(
        resolver.isDevRun(scriptPath: '/opt/ariami/ariami_cli'),
        isFalse,
      );
    });
  });
}
