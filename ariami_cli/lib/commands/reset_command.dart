import 'dart:io';

import 'package:ariami_core/ariami_core.dart';

import '../services/autostart_service.dart';
import '../services/cli_state_service.dart';
import '../services/daemon_service.dart';

/// Command to reset the Ariami CLI server's local state.
///
/// Two scopes are offered:
///   - Setup/config only: removes setup, server config and pairing state but
///     keeps the catalog database and accounts.
///   - Factory reset: removes everything Ariami owns under `~/.ariami_cli`
///     (database, accounts, sessions, caches) and disables start-on-boot.
///
/// The configured music folder is never deleted.
class ResetCommand {
  ResetCommand({
    DaemonService? daemonService,
    AutostartService? autostartService,
    CliStateService? stateService,
    ResetService resetService = const ResetService(),
  })  : _daemonService = daemonService ?? DaemonService(),
        _autostartService = autostartService ?? AutostartService(),
        _stateService = stateService ?? CliStateService(),
        _resetService = resetService;

  final DaemonService _daemonService;
  final AutostartService _autostartService;
  final CliStateService _stateService;
  final ResetService _resetService;

  static const _confirmationWord = 'RESET';

  /// Execute the reset command.
  ///
  /// [scope] forces a non-interactive scope (`setupOnly`/`factoryReset`).
  /// [skipConfirmation] skips the typed `RESET` prompt (for scripted use).
  Future<void> execute({
    ResetScope? scope,
    bool skipConfirmation = false,
  }) async {
    final chosen = scope ?? await _promptScope();
    if (chosen == null) {
      print('Cancelled. Nothing was changed.');
      return;
    }

    if (!skipConfirmation && !await _promptConfirmation()) {
      print('Cancelled. Nothing was changed.');
      return;
    }

    // The server holds the catalog database open, so stop it first.
    if (await _daemonService.isRunning()) {
      print('Ariami is currently running — stopping it first...');
      final stopped = await _daemonService.stopServer();
      if (!stopped) {
        print('ERROR: Could not stop the running server. '
            'Run "ariami_cli stop" and try again.');
        exit(1);
      }
      print('Server stopped.');
    }

    final musicFolderGuard = await _stateService.getMusicFolderPath();
    final plan = _buildPlan(chosen, musicFolderGuard);
    final result = await _resetService.execute(plan);

    if (chosen == ResetScope.factoryReset && _autostartService.isSupported) {
      final disabled = await _autostartService.disable();
      print(disabled
          ? 'Start-on-boot disabled.'
          : 'Note: could not disable start-on-boot automatically.');
    }

    _printSummary(chosen, result);
  }

  ResetPlan _buildPlan(ResetScope scope, String? musicFolderGuard) {
    // Always-cleared setup/config state.
    final files = <String>[
      CliStateService.getConfigFilePath(),
      CliStateService.getServerStateFilePath(),
      CliStateService.getLogFilePath(),
      CliStateService.getPidFilePath(),
    ];
    final directories = <String>[];

    final sqliteDatabases = <String>[];

    if (scope == ResetScope.factoryReset) {
      files.addAll([
        CliStateService.getUsersFilePath(),
        CliStateService.getSessionsFilePath(),
        CliStateService.getMetadataCacheFilePath(),
        CliStateService.getAutostartLogFilePath(),
      ]);
      sqliteDatabases.add(CliStateService.getCatalogDbFilePath());
      directories.addAll([
        CliStateService.getArtworkCacheDirPath(),
        CliStateService.getTranscodedCacheDirPath(),
      ]);
    }

    return ResetPlan(
      files: files,
      directories: directories,
      sqliteDatabases: sqliteDatabases,
      musicFolderPathGuard: musicFolderGuard,
    );
  }

  Future<ResetScope?> _promptScope() async {
    print('Reset Ariami');
    print('============');
    print('');
    print('What do you want to reset?');
    print('');
    print('  1. Setup/config only   '
        '(keeps your library database and accounts)');
    print('  2. Factory reset Ariami data   '
        '(removes database, accounts, sessions, cache)');
    print('  3. Cancel');
    print('');
    print('This will not delete your music files.');
    print('');
    stdout.write('Enter choice [1/2/3]: ');
    final answer = stdin.readLineSync()?.trim() ?? '';

    switch (answer) {
      case '1':
        return ResetScope.setupOnly;
      case '2':
        return ResetScope.factoryReset;
      default:
        return null;
    }
  }

  Future<bool> _promptConfirmation() async {
    stdout.write('Type RESET to continue: ');
    final answer = stdin.readLineSync()?.trim() ?? '';
    return answer == _confirmationWord;
  }

  void _printSummary(ResetScope scope, ResetResult result) {
    print('');
    if (result.hasFailures) {
      print('Reset completed with some problems:');
      for (final failure in result.failures) {
        print('  ! Could not remove ${failure.path}: ${failure.error}');
      }
    } else {
      print(scope == ResetScope.factoryReset
          ? '✓ Factory reset complete. Ariami data was removed; '
              'your music files were not touched.'
          : '✓ Setup reset complete. Your library and accounts were kept; '
              'your music files were not touched.');
    }

    for (final blocked in result.blocked) {
      print('  • Skipped ${blocked.path} (protected music library path).');
    }

    print('');
    print('Run "ariami_cli start" to set up Ariami again.');
  }
}
