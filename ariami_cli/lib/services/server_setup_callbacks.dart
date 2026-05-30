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
      print('Warning: No music folder configured yet.');
      print('Complete setup via web interface to configure music library.');
      return;
    }

    print('Music folder configured: $musicPath');
    print('Starting library scan...');

    try {
      _httpServer.libraryManager.scanMusicFolder(musicPath).then((_) {
        final library = _httpServer.libraryManager.library;
        print('');
        print('═══════════════════════════════════════════════════════');
        print('  ✓ Library scan completed!');
        print('  Albums: ${library?.totalAlbums ?? 0}');
        print('  Songs: ${library?.totalSongs ?? 0}');
        print('═══════════════════════════════════════════════════════');
        print('');
      }).catchError((e) {
        print('');
        print('Warning: Library scan failed: $e');
        print('');
      });
      print('✓ Library scan initiated');
    } catch (e) {
      print('Warning: Failed to start library scan: $e');
      print('Server will continue running, but library may be empty.');
    }
  }

  Future<TranscodeSlotsSnapshot> getTranscodeSlotsSnapshot() async {
    final override = await _stateService.getTranscodeSlotsOverride();
    return TranscodeSlotsPolicy.resolveSnapshot(override: override);
  }

  Future<bool> _handleSetMusicFolder(String path) async {
    try {
      print('[ServerRunner] Setting music folder path: $path');

      final validation = await MusicFolderPathHelper.validate(path);
      if (!validation.isValid) {
        print('[ServerRunner] ERROR: ${validation.message}');
        return false;
      }

      await _stateService.setMusicFolderPath(validation.path);
      print('[ServerRunner] ✓ Music folder path saved');

      return true;
    } catch (e) {
      print('[ServerRunner] ERROR setting music folder: $e');
      return false;
    }
  }

  Future<bool> _handleStartScan() async {
    try {
      print('[ServerRunner] Starting library scan...');

      final musicPath = await _stateService.getMusicFolderPath();
      if (musicPath == null || musicPath.isEmpty) {
        print('[ServerRunner] ERROR: No music folder path configured');
        return false;
      }

      _httpServer.libraryManager.scanMusicFolder(musicPath);
      print('[ServerRunner] ✓ Library scan initiated');

      return true;
    } catch (e) {
      print('[ServerRunner] ERROR starting scan: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> _handleGetScanStatus() async {
    final isScanning = _httpServer.libraryManager.isScanning;
    final library = _httpServer.libraryManager.library;

    double progress = 0.0;
    int songsFound = 0;
    int albumsFound = 0;
    String currentStatus = 'Initializing...';

    if (library != null) {
      progress = 1.0;
      songsFound = library.totalSongs;
      albumsFound = library.totalAlbums;
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
      'currentStatus': currentStatus,
    };
  }

  Future<bool> _handleMarkSetupComplete() async {
    try {
      print('[ServerRunner] Marking setup as complete...');
      await _stateService.markSetupComplete();
      print('[ServerRunner] ✓ Setup marked as complete');
      return true;
    } catch (e) {
      print('[ServerRunner] ERROR marking setup complete: $e');
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
