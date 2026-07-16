import 'package:ariami_core/ariami_core.dart';

import 'cli_state_service.dart';

/// Owns the setup and transcode-slot callbacks exposed by the CLI web server.
class ServerSetupCallbacks {
  ServerSetupCallbacks({
    required AriamiHttpServer httpServer,
    required CliStateService stateService,
  })  : _httpServer = httpServer,
        _stateService = stateService;

  final AriamiHttpServer _httpServer;
  final CliStateService _stateService;

  void register() {
    _httpServer.setSetupCallbacks(
      getConfiguredMusicFolderPath: _stateService.getMusicFolderPath,
      setMusicFolder: _handleSetMusicFolder,
      startScan: _handleStartScan,
      getScanStatus: _handleGetScanStatus,
      markSetupComplete: _handleMarkSetupComplete,
      getSetupStatus: _stateService.isSetupComplete,
    );

    _httpServer.setTranscodeSlotsCallbacks(
      getSnapshot: getTranscodeSlotsSnapshot,
      setOverride: _setTranscodeSlotsOverride,
    );
  }

  Future<void> startInitialScanIfConfigured() async {
    final musicPath = await _stateService.getMusicFolderPath();

    if (musicPath == null || musicPath.isEmpty) {
      return;
    }

    try {
      _httpServer.libraryManager.scanMusicFolder(musicPath);
    } catch (e) {
      print('Warning: Failed to start library scan: $e');
    }
  }

  Future<TranscodeSlotsSnapshot> getTranscodeSlotsSnapshot() async {
    final override = await _stateService.getTranscodeSlotsOverride();
    return TranscodeSlotsPolicy.resolveSnapshot(override: override);
  }

  Future<bool> _handleSetMusicFolder(String path) async {
    try {
      final validation = await MusicFolderPathHelper.validate(path);
      if (!validation.isValid) {
        return false;
      }

      await _stateService.setMusicFolderPath(validation.path);

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _handleStartScan() async {
    try {
      final musicPath = await _stateService.getMusicFolderPath();
      if (musicPath == null || musicPath.isEmpty) {
        return false;
      }

      _httpServer.libraryManager.scanMusicFolder(musicPath);

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _handleGetScanStatus() async {
    final isScanning = _httpServer.libraryManager.isScanning;
    final library = _httpServer.libraryManager.library;

    double progress = 0.0;
    int songsFound = 0;
    int albumsFound = 0;
    int scannedFileCount = 0;
    int skippedFileCount = 0;
    String currentStatus = 'Initializing...';

    if (library != null) {
      progress = 1.0;
      songsFound = library.totalSongs;
      albumsFound = library.totalAlbums;
      scannedFileCount = _httpServer.libraryManager.latestScannedFileCount;
      skippedFileCount =
          _httpServer.libraryManager.latestScanDiagnostics.skippedFileCount;
      currentStatus = 'Scan complete!';
    } else if (isScanning) {
      progress = 0.5;
      currentStatus = 'Scanning music library...';
    }

    return {
      'isScanning': isScanning,
      'progress': progress,
      'songsFound': songsFound,
      'albumsFound': albumsFound,
      'scannedFileCount': scannedFileCount,
      'skippedFileCount': skippedFileCount,
      'currentStatus': currentStatus,
    };
  }

  Future<bool> _handleMarkSetupComplete() async {
    try {
      await _stateService.markSetupComplete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<TranscodeSlotsSnapshot> _setTranscodeSlotsOverride(int? slots) async {
    if (slots != null) {
      TranscodeSlotsPolicy.validateSlots(slots);
    }
    await _stateService.setTranscodeSlotsOverride(slots);
    return getTranscodeSlotsSnapshot();
  }
}
