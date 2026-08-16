import 'dart:async';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';

import 'autostart_service.dart';
import 'cli_reset_plan.dart';
import 'cli_state_service.dart';

/// Exposes machine-level server settings to the web dashboard: where the music
/// library lives, whether Ariami starts at boot, and resetting this host's
/// Ariami data.
///
/// These live on the CLI rather than in `ariami_core` because they are
/// specific to running Ariami as a headless service. Desktop offers the same
/// settings through its own in-process UI.
class ServerHostControls {
  ServerHostControls({
    required AriamiHttpServer httpServer,
    CliStateService? stateService,
    AutostartService? autostartService,
    ResetService resetService = const ResetService(),
  })  : _httpServer = httpServer,
        _stateService = stateService ?? CliStateService(),
        _autostartService = autostartService ?? AutostartService(),
        _resetService = resetService;

  final AriamiHttpServer _httpServer;
  final CliStateService _stateService;
  final AutostartService _autostartService;
  final ResetService _resetService;

  /// Grace period before exiting after a reset, so the HTTP response reaches
  /// the browser before the process goes away.
  static const Duration _shutdownDelay = Duration(milliseconds: 750);

  void register() {
    _httpServer.setHostControlCallbacks(
      getSnapshot: _snapshot,
      setAutostartEnabled: _setAutostartEnabled,
      reset: _reset,
    );
  }

  Future<HostControlsSnapshot> _snapshot() async {
    final musicFolderPath = await _stateService.getMusicFolderPath();
    final supported = _autostartService.isSupported;
    return HostControlsSnapshot(
      musicFolderPath: musicFolderPath,
      autostartSupported: supported,
      autostartEnabled: supported && await _autostartService.isEnabled(),
      resetSupported: true,
    );
  }

  Future<HostControlsSnapshot> _setAutostartEnabled(bool enabled) async {
    if (!_autostartService.isSupported) {
      throw StateError('Start at boot is not supported on this platform');
    }

    final ok = enabled
        ? await _autostartService.enable()
        : await _autostartService.disable();
    if (!ok) {
      throw StateError(
        enabled
            ? 'Could not enable start at boot on this machine'
            : 'Could not disable start at boot on this machine',
      );
    }

    return _snapshot();
  }

  Future<HostResetOutcome> _reset(ResetScope scope) async {
    final musicFolderGuard = await _stateService.getMusicFolderPath();
    final result = await _resetService.execute(
      buildCliResetPlan(scope, musicFolderGuard),
    );

    if (scope == ResetScope.factoryReset && _autostartService.isSupported) {
      await _autostartService.disable();
    }

    final failedPaths = result.failures.map((f) => f.path).toList();
    final success = !result.hasFailures;

    // The reset removed the state this process is serving from — and for a
    // factory reset, the catalog database it holds open. Stop rather than
    // keep answering from state that no longer exists on disk.
    unawaited(_shutdownAfterReset());

    return HostResetOutcome(
      success: success,
      message: success
          ? (scope == ResetScope.factoryReset
              ? 'Factory reset complete. Ariami data was removed and the '
                  'server has stopped; your music files were not touched. '
                  'Run "ariami_cli start" to set Ariami up again.'
              : 'Setup reset complete. Your library and accounts were kept '
                  'and the server has stopped; your music files were not '
                  'touched. Run "ariami_cli start" to set Ariami up again.')
          : 'Reset finished with problems. Some files could not be removed; '
              'the server has stopped. Run "ariami_cli reset" on the machine '
              'to finish clearing them.',
      failedPaths: failedPaths,
    );
  }

  Future<void> _shutdownAfterReset() async {
    await Future<void>.delayed(_shutdownDelay);
    await _httpServer.stop();
    exit(0);
  }
}
