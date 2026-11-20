import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of attempting to locate bundled Ariami Web player assets.
class WebPlayerAssetsResolution {
  const WebPlayerAssetsResolution({
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

/// Resolves Ariami Web player asset directories for dev and release layouts.
class WebPlayerAssetsResolver {
  const WebPlayerAssetsResolver();

  /// Candidate paths in search order (not yet verified to exist).
  List<String> buildCandidates({
    String? cwd,
    String? executableDir,
    String? scriptPath,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final workingDir = p.normalize(cwd ?? Directory.current.path);
    final exeDir = p.normalize(
      executableDir ?? File(Platform.resolvedExecutable).parent.path,
    );

    final candidates = <String>[];
    final override = env['ARIAMI_WEB_PLAYER_DIR']?.trim();
    if (override != null && override.isNotEmpty) {
      candidates.add(p.normalize(override));
    }

    candidates.addAll([
      p.normalize(p.join(exeDir, 'web_player')),
      p.normalize(p.join(exeDir, '..', 'web_player')),
      p.normalize(p.join(exeDir, '..', 'Resources', 'web_player')),
      p.normalize(p.join(workingDir, 'web_player')),
      p.normalize(p.join(workingDir, '..', 'ariami_web', 'build', 'web')),
      p.normalize(p.join(workingDir, 'ariami_web', 'build', 'web')),
    ]);

    if (scriptPath != null && scriptPath.endsWith('.dart')) {
      final scriptDir = p.normalize(p.dirname(scriptPath));
      final packageRoot = p.basename(scriptDir) == 'bin'
          ? p.dirname(scriptDir)
          : scriptDir;
      candidates.addAll([
        p.normalize(p.join(packageRoot, '..', 'ariami_web', 'build', 'web')),
        p.normalize(p.join(packageRoot, 'web_player')),
      ]);
    }

    return candidates;
  }

  /// Resolve the first existing web player assets directory as an absolute path.
  Future<WebPlayerAssetsResolution> resolve({
    String? cwd,
    String? executableDir,
    String? scriptPath,
    Map<String, String>? environment,
    bool Function(String path)? exists,
  }) async {
    final workingDir = p.normalize(cwd ?? Directory.current.path);
    final exeDir = p.normalize(
      executableDir ?? File(Platform.resolvedExecutable).parent.path,
    );
    final script = scriptPath ?? _defaultScriptPath();
    final checkExists =
        exists ?? (path) => File(p.join(path, 'index.html')).existsSync();

    final candidates = buildCandidates(
      cwd: workingDir,
      executableDir: exeDir,
      scriptPath: script,
      environment: environment,
    );

    for (final candidate in candidates) {
      final absolutePath = p.normalize(p.absolute(candidate));
      if (checkExists(absolutePath)) {
        return WebPlayerAssetsResolution(
          path: absolutePath,
          cwd: workingDir,
          executableDir: exeDir,
          candidatesChecked: candidates,
        );
      }
    }

    return WebPlayerAssetsResolution(
      cwd: workingDir,
      executableDir: exeDir,
      candidatesChecked: candidates,
    );
  }

  static String? _defaultScriptPath() {
    try {
      final scriptUri = Platform.script;
      if (scriptUri.scheme == 'file') {
        return scriptUri.toFilePath();
      }
    } catch (_) {}
    return null;
  }
}
