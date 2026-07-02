import 'dart:async';

import 'package:ariami_core/ariami_core.dart';

import 'cli_state_service.dart';

/// Owns the setup and transcode-slot callbacks exposed by the CLI web server.
class ServerSetupCallbacks {
  ServerSetupCallbacks({
    required AriamiHttpServer httpServer,
    required CliStateService stateService,
    Future<String?> Function()? getMusicFolderPath,
  })  : _httpServer = httpServer,
        _stateService = stateService,
        _getMusicFolderPath =
            getMusicFolderPath ?? stateService.getMusicFolderPath;

  final AriamiHttpServer _httpServer;
  final CliStateService _stateService;
  final Future<String?> Function() _getMusicFolderPath;

  Future<void>? _activeScan;
  String? _lastScanError;

  void register() {
    _httpServer.setSetupCallbacks(
      getConfiguredMusicFolderPath: _getMusicFolderPath,
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
    final musicPath = await _getMusicFolderPath();

    if (musicPath == null || musicPath.isEmpty) {
      return;
    }

    try {
      final validation = await MusicFolderPathHelper.validate(musicPath);
      if (!validation.isValid) {
        print('Warning: ${validation.message}');
        return;
      }
      _startScan(validation.path);
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
      final musicPath = await _getMusicFolderPath();
      if (musicPath == null || musicPath.isEmpty) {
        _lastScanError = 'No music folder is configured.';
        return false;
      }

      final validation = await MusicFolderPathHelper.validate(musicPath);
      if (!validation.isValid) {
        _lastScanError = validation.message;
        return false;
      }

      return _startScan(validation.path);
    } catch (e) {
      _lastScanError = e.toString();
      return false;
    }
  }

  bool _startScan(String musicPath) {
    final manager = _httpServer.libraryManager;
    if (manager.isScanning || _activeScan != null) {
      return false;
    }

    _lastScanError = null;
    final previousScanTime = manager.lastScanTime;
    final scan = manager.scanMusicFolder(musicPath);
    _activeScan = scan;
    unawaited(_observeScan(scan, previousScanTime));
    return true;
  }

  Future<void> _observeScan(
    Future<void> scan,
    DateTime? previousScanTime,
  ) async {
    try {
      await scan;
      if (_httpServer.libraryManager.lastScanTime == previousScanTime) {
        _lastScanError = 'The library scan did not complete successfully.';
      }
    } catch (e) {
      _lastScanError = e.toString();
    } finally {
      _activeScan = null;
    }
  }

  Future<Map<String, dynamic>> _handleGetScanStatus() async {
    final manager = _httpServer.libraryManager;
    final isScanning = manager.isScanning || _activeScan != null;
    final library = manager.library;
    final diagnostics = manager.latestScanDiagnostics;

    double progress = 0.0;
    int songsFound = 0;
    int albumsFound = 0;
    String currentStatus = 'Initializing...';

    if (isScanning) {
      progress = 0.5;
      currentStatus = 'Scanning music library...';
    } else if (_lastScanError != null) {
      currentStatus = 'Scan failed: $_lastScanError';
    } else if (library != null) {
      progress = 1.0;
      songsFound = library.totalSongs;
      albumsFound = library.totalAlbums;
      currentStatus = diagnostics.skippedFileCount > 0
          ? 'Scan complete with ${diagnostics.skippedFileCount} skipped file(s)'
          : 'Scan complete!';
    }

    return {
      'isScanning': isScanning,
      'progress': progress,
      'songsFound': songsFound,
      'albumsFound': albumsFound,
      'currentStatus': currentStatus,
      'scanError': _lastScanError,
      'skippedFileCount': isScanning ? 0 : diagnostics.skippedFileCount,
      'failedFiles': isScanning
          ? const <Map<String, dynamic>>[]
          : diagnostics.failedFiles.map((file) => file.toJson()).toList(),
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
