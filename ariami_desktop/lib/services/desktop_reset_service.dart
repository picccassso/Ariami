import 'package:ariami_core/ariami_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'autostart_service.dart';
import 'desktop_state_service.dart';

/// Coordinates resetting the desktop app's local state.
///
/// Stops the running server first (so the catalog database handle is released),
/// then clears preferences and removes Ariami-owned data via the shared
/// [ResetService]. The configured music folder is passed as a guard and is
/// never deleted.
class DesktopResetService {
  DesktopResetService({
    required AriamiHttpServer httpServer,
    DesktopStateService? stateService,
    AutostartService? autostartService,
    ResetService resetService = const ResetService(),
  })  : _httpServer = httpServer,
        _stateService = stateService ?? DesktopStateService(),
        _autostartService = autostartService ?? AutostartService(),
        _resetService = resetService;

  final AriamiHttpServer _httpServer;
  final DesktopStateService _stateService;
  final AutostartService _autostartService;
  final ResetService _resetService;

  /// Perform a reset of the given [scope]. Returns the file-deletion result for
  /// factory resets (null for setup-only, which only clears preferences).
  Future<ResetResult?> reset(ResetScope scope) async {
    // Read the music folder before clearing preferences so it can guard the
    // deletion, then stop the server to release the catalog database handle.
    final musicFolderGuard = await _readMusicFolderPath();
    if (_httpServer.isRunning) {
      await _httpServer.stop();
    }

    if (scope == ResetScope.setupOnly) {
      await _stateService.clearSetupPreferences();
      return null;
    }

    await _stateService.clearAllPreferences();

    final plan = ResetPlan(
      files: [
        await _stateService.getMetadataCacheFilePath(),
        await _stateService.getUsersFilePath(),
        await _stateService.getSessionsFilePath(),
      ],
      sqliteDatabases: [
        await _stateService.getCatalogDbFilePath(),
      ],
      directories: [
        await _stateService.getArtworkCacheDirPath(),
        await _stateService.getTranscodedCacheDirPath(),
      ],
      musicFolderPathGuard: musicFolderGuard,
    );
    final result = await _resetService.execute(plan);

    // Factory reset returns the machine to a pre-install state.
    if (_autostartService.isSupported) {
      try {
        await _autostartService.setEnabled(false);
      } catch (e) {
        print('[Reset] Failed to disable autostart: $e');
      }
    }

    return result;
  }

  Future<String?> _readMusicFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('music_folder_path');
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }
}
