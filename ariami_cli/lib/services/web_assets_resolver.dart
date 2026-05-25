import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of attempting to locate bundled Flutter web assets.
class WebAssetsResolution {
  const WebAssetsResolution({
    required this.cwd,
    required this.executableDir,
    required this.candidatesChecked,
    this.path,
  });

  final String? path;
  final String cwd;
  final String executableDir;
  final List<String> candidatesChecked;

  bool get found => path != null;
}

/// Resolves Flutter web asset directories for dev and release layouts.
class WebAssetsResolver {
  /// Candidate paths in search order (not yet verified to exist).
  List<String> buildCandidates({
    String? cwd,
    String? executableDir,
    String? scriptPath,
  }) {
    final workingDir = p.normalize(cwd ?? Directory.current.path);
    final exeDir = p.normalize(
      executableDir ?? File(Platform.resolvedExecutable).parent.path,
    );

    final candidates = <String>[
      p.join(workingDir, 'build', 'web'),
      p.join(workingDir, 'web'),
      p.join(exeDir, 'web'),
      p.join(exeDir, 'build', 'web'),
    ];

    if (scriptPath != null && scriptPath.endsWith('.dart')) {
      final scriptDir = p.normalize(p.dirname(scriptPath));
      final packageRoot = p.basename(scriptDir) == 'bin'
          ? p.dirname(scriptDir)
          : scriptDir;
      candidates.addAll([
        p.join(packageRoot, 'build', 'web'),
        p.join(packageRoot, 'web'),
      ]);
    }

    return candidates;
  }

  /// Resolve the first existing web assets directory as an absolute path.
  Future<WebAssetsResolution> resolve({
    String? cwd,
    String? executableDir,
    String? scriptPath,
    bool Function(String path)? exists,
  }) async {
    final workingDir = p.normalize(cwd ?? Directory.current.path);
    final exeDir = p.normalize(
      executableDir ?? File(Platform.resolvedExecutable).parent.path,
    );
    final script = scriptPath ?? Platform.script.toFilePath();
    final checkExists = exists ?? (path) => Directory(path).existsSync();

    final candidates = buildCandidates(
      cwd: workingDir,
      executableDir: exeDir,
      scriptPath: script,
    );

    for (final candidate in candidates) {
      final absolutePath = p.normalize(p.absolute(candidate));
      if (checkExists(absolutePath)) {
        return WebAssetsResolution(
          path: absolutePath,
          cwd: workingDir,
          executableDir: exeDir,
          candidatesChecked: candidates,
        );
      }
    }

    return WebAssetsResolution(
      cwd: workingDir,
      executableDir: exeDir,
      candidatesChecked: candidates,
    );
  }

  /// Whether this looks like a `dart run` dev invocation rather than release.
  bool isDevRun({String? scriptPath}) {
    final script = scriptPath ?? Platform.script.toFilePath();
    return script.endsWith('.dart');
  }

  void printNotFoundError(WebAssetsResolution resolution, {String? scriptPath}) {
    print('ERROR: Web UI not found.');
    print('');
    print('Current working directory:');
    print('  ${resolution.cwd}');
    print('Executable directory:');
    print('  ${resolution.executableDir}');
    print('');
    print('Checked these locations:');
    for (final candidate in resolution.candidatesChecked) {
      print('  - ${p.normalize(p.absolute(candidate))}');
    }
    print('');

    if (isDevRun(scriptPath: scriptPath)) {
      print('Build the web UI from the ariami_cli package:');
      print('  cd ariami_cli');
      print('  flutter build web -t lib/web/main.dart');
    } else {
      print(
        'Run from the release directory or ensure the web/ folder is next to '
        'the executable.',
      );
    }
    print('');
  }
}
