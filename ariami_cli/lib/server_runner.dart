import 'dart:io';
import 'dart:async';
import 'package:ariami_core/ariami_core.dart';
import 'services/cli_state_service.dart';
import 'services/cli_tailscale_service.dart';
import 'services/daemon_service.dart';

/// ServerRunner handles the actual execution of the Ariami server
/// Can run in both foreground (setup) and background modes
class ServerRunner {
  final AriamiHttpServer _httpServer = AriamiHttpServer();
  final CliStateService _stateService = CliStateService();
  final LibraryManager _libraryManager = LibraryManager();
  final CliTailscaleService _tailscaleService = CliTailscaleService();
  final DaemonService _daemonService = DaemonService();

  bool _isShuttingDown = false;
  int _serverPort = 8080;

  /// Run the Ariami server
  ///
  /// - [port]: Server port (default: 8080)
  /// - [isSetupMode]: If true, server runs for setup without library scanning
  Future<void> run({required int port, required bool isSetupMode}) async {
    print('Ariami Server starting...');
    _serverPort = port;

    try {
      // Set up signal handlers for graceful shutdown
      _setupSignalHandlers();

      // Configure web assets path (dev: build/web, release: web)
      final webPath = Directory('build/web').existsSync() ? 'build/web' : 'web';
      _httpServer.setWebAssetsPath(webPath);

      // Configure Tailscale status callback
      _httpServer.setTailscaleStatusCallback(() => _tailscaleService.getStatus());

      // Configure setup callbacks
      _httpServer.setSetupCallbacks(
        setMusicFolder: _handleSetMusicFolder,
        startScan: _handleStartScan,
        getScanStatus: _handleGetScanStatus,
        markSetupComplete: _handleMarkSetupComplete,
        getSetupStatus: _handleGetSetupStatus,
      );

      // Configure transition callback for setup mode
      if (isSetupMode) {
        _httpServer.setTransitionToBackgroundCallback(_handleTransitionToBackground);
      }

      // Detect best IP for advertising to mobile clients (Tailscale > LAN > localhost)
      final advertisedIp = await _tailscaleService.getBestAdvertisedIp();

      // Start HTTP server - bind to 0.0.0.0 to accept connections from any interface
      print('Starting HTTP server on 0.0.0.0:$port...');
      await _httpServer.start(
        advertisedIp: advertisedIp,
        bindAddress: '0.0.0.0',
        port: port,
      );
      print('✓ HTTP server started successfully');
      print('✓ Server accessible at: http://$advertisedIp:$port');

      // If not in setup mode, initialize library
      if (!isSetupMode) {
        final musicPath = await _stateService.getMusicFolderPath();

        if (musicPath != null && musicPath.isNotEmpty) {
          print('Music folder configured: $musicPath');
          print('Starting library scan...');

          try {
            // Scan library in background and log completion
            _libraryManager.scanMusicFolder(musicPath).then((_) {
              final library = _libraryManager.library;
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
        } else {
          print('Warning: No music folder configured yet.');
          print('Complete setup via web interface to configure music library.');
        }
      }

      print('');
      print('═══════════════════════════════════════════════════════');
      print('  Ariami Server is running');
      print('  URL: http://localhost:$port');
      if (isSetupMode) {
        print('  Mode: Setup (first-time configuration)');
      } else {
        print('  Mode: Normal operation');
      }
      print('═══════════════════════════════════════════════════════');
      print('');

      // Wait for shutdown signal
      await _waitForShutdown();

      // Graceful shutdown
      await _shutdown();

    } catch (e, stackTrace) {
      print('');
      print('ERROR: Server failed to start');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      print('');

      // Attempt cleanup
      try {
        await _httpServer.stop();
      } catch (_) {
        // Ignore cleanup errors
      }

      exit(1);
    }
  }

  /// Set up signal handlers for graceful shutdown
  void _setupSignalHandlers() {
    // Handle SIGTERM (kill command, systemd stop, etc.)
    ProcessSignal.sigterm.watch().listen((signal) {
      print('');
      print('Received SIGTERM signal, shutting down gracefully...');
      _triggerShutdown();
    });

    // Handle SIGINT (Ctrl+C)
    ProcessSignal.sigint.watch().listen((signal) {
      print('');
      print('Received SIGINT signal (Ctrl+C), shutting down gracefully...');
      _triggerShutdown();
    });
  }

  /// Completer that completes when shutdown is requested
  final Completer<void> _shutdownCompleter = Completer<void>();

  /// Trigger shutdown
  void _triggerShutdown() {
    if (!_shutdownCompleter.isCompleted) {
      _shutdownCompleter.complete();
    }
  }

  /// Wait for shutdown signal
  Future<void> _waitForShutdown() async {
    await _shutdownCompleter.future;
  }

  /// Perform graceful shutdown
  Future<void> _shutdown() async {
    if (_isShuttingDown) {
      return; // Already shutting down
    }

    _isShuttingDown = true;
    print('');
    print('Shutting down Ariami server...');

    try {
      // Stop HTTP server
      print('Stopping HTTP server...');
      await _httpServer.stop();
      print('✓ HTTP server stopped');

      // Note: LibraryManager doesn't need explicit cleanup
      // as it's just in-memory state

      print('✓ Server shutdown complete');
      print('');
    } catch (e) {
      print('Warning: Error during shutdown: $e');
    }
  }

  /// Setup callback: Set music folder path
  Future<bool> _handleSetMusicFolder(String path) async {
    try {
      print('[ServerRunner] Setting music folder path: $path');

      // Validate path exists
      final dir = Directory(path);
      if (!await dir.exists()) {
        print('[ServerRunner] ERROR: Path does not exist: $path');
        return false;
      }

      // Save the music folder path
      await _stateService.setMusicFolderPath(path);
      print('[ServerRunner] ✓ Music folder path saved');

      return true;
    } catch (e) {
      print('[ServerRunner] ERROR setting music folder: $e');
      return false;
    }
  }

  /// Setup callback: Start library scan
  Future<bool> _handleStartScan() async {
    try {
      print('[ServerRunner] Starting library scan...');

      // Get music folder path
      final musicPath = await _stateService.getMusicFolderPath();
      if (musicPath == null || musicPath.isEmpty) {
        print('[ServerRunner] ERROR: No music folder path configured');
        return false;
      }

      // Start scanning in background
      _libraryManager.scanMusicFolder(musicPath);
      print('[ServerRunner] ✓ Library scan initiated');

      return true;
    } catch (e) {
      print('[ServerRunner] ERROR starting scan: $e');
      return false;
    }
  }

  /// Setup callback: Get scan status
  Future<Map<String, dynamic>> _handleGetScanStatus() async {
    final isScanning = _libraryManager.isScanning;
    final library = _libraryManager.library;

    // Calculate progress based on scan state
    double progress = 0.0;
    int songsFound = 0;
    int albumsFound = 0;
    String currentStatus = 'Initializing...';

    if (library != null) {
      // Scan complete
      progress = 1.0;
      songsFound = library.totalSongs;
      albumsFound = library.totalAlbums;
      currentStatus = 'Scan complete!';
    } else if (isScanning) {
      // Scanning in progress - show indeterminate progress
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

  /// Setup callback: Mark setup as complete
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

  /// Setup callback: Check if setup is complete
  Future<bool> _handleGetSetupStatus() async {
    return await _stateService.isSetupComplete();
  }

  /// Handle transition from foreground setup mode to background daemon mode
  Future<Map<String, dynamic>> _handleTransitionToBackground() async {
    print('[ServerRunner] Transitioning to background mode...');

    try {
      // Spawn background process with --server-mode flag
      final pid = await _daemonService.startServerInBackground([
        '--server-mode',
        '--port',
        _serverPort.toString(),
      ]);

      if (pid == null) {
        print('[ServerRunner] ERROR: Failed to spawn background process');
        return {
          'success': false,
          'message': 'Failed to spawn background process',
        };
      }

      // Save server state for status command
      await _daemonService.saveServerState({
        'port': _serverPort,
        'pid': pid,
        'started_at': DateTime.now().toIso8601String(),
      });

      print('[ServerRunner] Background process spawned with PID: $pid');
      print('[ServerRunner] Scheduling foreground shutdown...');

      // Schedule foreground shutdown after short delay to allow response to be sent
      Future.delayed(const Duration(milliseconds: 500), () async {
        print('[ServerRunner] Triggering shutdown of foreground process...');
        _triggerShutdown();

        // Wait for shutdown to complete
        await Future.delayed(const Duration(milliseconds: 500));

        // Explicitly exit (signal handlers keep isolate alive otherwise)
        exit(0);
      });

      return {
        'success': true,
        'message': 'Transitioning to background mode',
        'pid': pid,
      };
    } catch (e) {
      print('[ServerRunner] Transition error: $e');
      return {
        'success': false,
        'message': 'Transition failed: $e',
      };
    }
  }
}
