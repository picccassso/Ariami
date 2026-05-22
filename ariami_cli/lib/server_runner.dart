import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:ariami_core/ariami_core.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'services/cli_state_service.dart';
import 'services/cli_tailscale_service.dart';
import 'services/daemon_service.dart';

/// ServerRunner handles the actual execution of the Ariami server
/// Can run in both foreground (setup) and background modes
class ServerRunner {
  final AriamiHttpServer _httpServer = AriamiHttpServer();
  final CliStateService _stateService = CliStateService();
  final CliTailscaleService _tailscaleService = CliTailscaleService();
  final DaemonService _daemonService = DaemonService();

  bool _isShuttingDown = false;
  int _serverPort = 8080;

  // Store signal subscriptions so we can cancel them during transition
  StreamSubscription<ProcessSignal>? _sigtermSubscription;
  StreamSubscription<ProcessSignal>? _sigintSubscription;

  /// Run the Ariami server
  ///
  /// - [port]: Server port (default: 8080)
  /// - [isSetupMode]: If true, server runs for setup without library scanning
  /// - [isServerMode]: If true, running as background daemon (write own PID)
  Future<void> run(
      {required int port,
      required bool isSetupMode,
      bool isServerMode = false}) async {
    print('Ariami Server starting...');
    _serverPort = port;

    try {
      final featureFlags = _loadFeatureFlagsFromEnvironment();
      _validateFeatureFlagInvariantsOrThrow(featureFlags);
      _httpServer.setFeatureFlags(featureFlags);

      await _stateService.ensureConfigDir();

      // Configure metadata cache (also initializes catalog repository for v2 mode).
      final cachePath =
          p.join(CliStateService.getConfigDir(), 'metadata_cache.json');
      _httpServer.libraryManager.setCachePath(cachePath);

      if (featureFlags.enableV2Api &&
          _httpServer.libraryManager.createCatalogRepository() == null) {
        throw StateError(
          'Invalid startup configuration: enableV2Api=true requires catalog '
          'repository availability. Failed to initialize catalog at $cachePath.',
        );
      }

      // Detect platform early for download limits
      final isPi = _isRaspberryPi();
      final isPi5 = isPi && _isRaspberryPi5();

      // Set up signal handlers for graceful shutdown
      _setupSignalHandlers();

      // In server mode, write our own PID to the file (fixes Linux daemon PID tracking)
      // The shell command that spawned us may have recorded the wrong PID
      if (isServerMode) {
        await _daemonService.saveServerPid(pid);
        print('Server PID: $pid');
      }

      // Configure web assets path (dev: build/web, release: web)
      final webPath = Directory('build/web').existsSync() ? 'build/web' : 'web';
      _httpServer.setWebAssetsPath(webPath);

      // Configure Tailscale status callback
      _httpServer
          .setTailscaleStatusCallback(() => _tailscaleService.getStatus());

      _httpServer.setEndpointDiscoveryCallback(() async {
        final ts = await _tailscaleService.getTailscaleIp();
        final lan = await _tailscaleService.getLanIp();
        return NetworkEndpoints(tailscaleIp: ts, lanIp: lan);
      });

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
        _httpServer
            .setTransitionToBackgroundCallback(_handleTransitionToBackground);
      }

      // Initialize auth services (users/sessions storage)
      await _stateService.ensureConfigDir();
      await _httpServer.initializeAuth(
        usersFilePath: CliStateService.getUsersFilePath(),
        sessionsFilePath: CliStateService.getSessionsFilePath(),
      );

      // Configure download limits and cache policy (platform + storage aware)
      final musicPathForLimits = await _stateService.getMusicFolderPath();
      final musicStorageType = isPi
          ? await _detectStorageType(musicPathForLimits)
          : StorageType.unknown;
      final stateStorageType = isPi
          ? await _detectStorageType(CliStateService.getConfigDir())
          : StorageType.unknown;
      final storageProfile = selectStorageProfile(
        isPi: isPi,
        musicStorageType: musicStorageType,
        stateStorageType: stateStorageType,
        override: Platform.environment['ARIAMI_STORAGE_PROFILE'],
      );
      final limits = _selectDownloadLimits(
        isPi: isPi,
        isPi5: isPi5,
        storageType: musicStorageType,
      );
      final cachePolicy = selectCachePolicy(
        isPi: isPi,
        isPi5: isPi5,
        storageProfile: storageProfile,
      );
      _httpServer.setDownloadLimits(
        maxConcurrent: limits.maxConcurrent,
        maxQueue: limits.maxQueue,
        maxConcurrentPerUser: limits.maxConcurrentPerUser,
        maxQueuePerUser: limits.maxQueuePerUser,
      );
      print('Storage profile: ${storageProfile.name} '
          '(music=${musicStorageType.name}, state=${stateStorageType.name})');

      // Advertise both LAN and Tailscale so mobile can prefer LAN when reachable
      // (same contract as ariami_desktop).
      final tailscaleIp = await _tailscaleService.getTailscaleIp();
      final lanIp = await _tailscaleService.getLanIp();
      final advertisedIp = tailscaleIp ?? lanIp ?? 'localhost';

      // Start HTTP server - bind to 0.0.0.0 to accept connections from any interface
      print('Starting HTTP server on 0.0.0.0:$port...');
      await _httpServer.start(
        advertisedIp: advertisedIp,
        tailscaleIp: tailscaleIp,
        lanIp: lanIp,
        bindAddress: '0.0.0.0',
        port: port,
      );
      print('✓ HTTP server started successfully');
      print('✓ Server accessible at: http://$advertisedIp:$port');

      // Initialize transcoding service for quality-based streaming
      // Platform-aware settings: conservative for Pi, higher for desktop
      final transcodingCachePath =
          p.join(CliStateService.getConfigDir(), 'transcoded_cache');

      // Detect platform for concurrency settings
      final int maxConcurrency;
      final int maxDownloadConcurrency;
      final int maxCacheSizeMB;

      if (isPi) {
        // Raspberry Pi: Pi 5 can sustain more transcode work; older Pi models
        // keep a lower cap to preserve playback responsiveness.
        maxConcurrency = isPi5 ? 4 : 3;
        maxDownloadConcurrency = isPi5 ? 4 : 3;
        maxCacheSizeMB = cachePolicy.transcodeCacheSizeMB;
        print(
            'Platform: Raspberry Pi${isPi5 ? ' 5' : ''} detected - using Pi transcoding settings (streaming+download slots)');
      } else if (Platform.isMacOS || Platform.isWindows) {
        // Desktop: more resources available
        maxConcurrency = 2;
        maxDownloadConcurrency = 8;
        maxCacheSizeMB = cachePolicy.transcodeCacheSizeMB;
        print(
            'Platform: Desktop (${Platform.operatingSystem}) - using standard transcoding settings');
      } else {
        // Linux desktop or other: moderate settings
        maxConcurrency = 2;
        maxDownloadConcurrency = 3;
        maxCacheSizeMB = cachePolicy.transcodeCacheSizeMB;
        print('Platform: Linux - using moderate transcoding settings');
      }

      final transcodingService = TranscodingService(
        cacheDirectory: transcodingCachePath,
        maxCacheSizeMB: maxCacheSizeMB,
        maxConcurrency: maxConcurrency,
        maxDownloadConcurrency: maxDownloadConcurrency,
        transcodeTimeout:
            Duration(minutes: isPi ? 10 : 5), // Longer timeout for Pi
        indexPersistInterval: cachePolicy.transcodeIndexPersistInterval,
      );
      _httpServer.setTranscodingService(transcodingService);
      print('Transcoding cache: $transcodingCachePath');
      print(
          'Transcoding limits: maxConcurrency=$maxConcurrency, maxDownloadConcurrency=$maxDownloadConcurrency');
      print('Transcoding cache policy: maxCacheSizeMB=$maxCacheSizeMB, '
          'indexPersistInterval=${cachePolicy.transcodeIndexPersistInterval.inSeconds}s');

      // Initialize artwork service for thumbnail generation
      final artworkCachePath =
          p.join(CliStateService.getConfigDir(), 'artwork_cache');
      final artworkService = ArtworkService(
        cacheDirectory: artworkCachePath,
        maxCacheSizeMB: cachePolicy.artworkCacheSizeMB,
        touchOnCacheHit: cachePolicy.touchArtworkOnCacheHit,
        touchThrottle: cachePolicy.artworkTouchThrottle,
      );
      _httpServer.setArtworkService(artworkService);
      print('Artwork cache: $artworkCachePath');
      print(
          'Artwork cache policy: maxCacheSizeMB=${cachePolicy.artworkCacheSizeMB}, '
          'touchOnCacheHit=${cachePolicy.touchArtworkOnCacheHit}, '
          'touchThrottle=${cachePolicy.artworkTouchThrottle.inSeconds}s');

      // Check Sonic availability for audio transcoding.
      final sonicAvailable = await transcodingService.isSonicAvailable();
      if (sonicAvailable) {
        print('✓ Sonic available - audio transcoding enabled');
      } else {
        print(
            '⚠ Sonic not available - audio transcoding disabled (will serve original files)');
      }

      // Artwork thumbnails still rely on FFmpeg.
      final artworkFfmpegAvailable = await artworkService.isFFmpegAvailable();
      if (artworkFfmpegAvailable) {
        print('✓ FFmpeg available - artwork thumbnails enabled');
      } else {
        print(
            '⚠ FFmpeg not found - artwork thumbnails disabled (original artwork only)');
      }

      // If not in setup mode, initialize library
      if (!isSetupMode) {
        final musicPath = await _stateService.getMusicFolderPath();

        if (musicPath != null && musicPath.isNotEmpty) {
          print('Music folder configured: $musicPath');
          print('Starting library scan...');

          try {
            // Scan library in background and log completion
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

      // Rethrow so caller can handle (e.g., retry logic in server mode)
      rethrow;
    }
  }

  AriamiFeatureFlags _loadFeatureFlagsFromEnvironment() {
    bool parseFlag(String key, {required bool defaultValue}) {
      final value = Platform.environment[key];
      if (value == null) return defaultValue;

      final normalized = value.trim().toLowerCase();
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'on';
    }

    return AriamiFeatureFlags(
      enableV2Api: parseFlag('ARIAMI_ENABLE_V2_API', defaultValue: true),
      enableCatalogWrite:
          parseFlag('ARIAMI_ENABLE_CATALOG_WRITE', defaultValue: false),
      enableCatalogRead:
          parseFlag('ARIAMI_ENABLE_CATALOG_READ', defaultValue: false),
      enableArtworkPrecompute:
          parseFlag('ARIAMI_ENABLE_ARTWORK_PRECOMPUTE', defaultValue: false),
      enableDownloadJobs:
          parseFlag('ARIAMI_ENABLE_DOWNLOAD_JOBS', defaultValue: true),
      enableApiScopedAuthForCliWeb: parseFlag(
        'ARIAMI_ENABLE_API_SCOPED_AUTH_FOR_CLI_WEB',
        defaultValue: true,
      ),
    );
  }

  void _validateFeatureFlagInvariantsOrThrow(AriamiFeatureFlags flags) {
    if (flags.enableDownloadJobs && !flags.enableV2Api) {
      throw StateError(
        'Invalid feature flag configuration: enableDownloadJobs=true '
        'requires enableV2Api=true.',
      );
    }
  }

  /// Set up signal handlers for graceful shutdown
  void _setupSignalHandlers() {
    // Handle SIGTERM (kill command, systemd stop, etc.)
    _sigtermSubscription = ProcessSignal.sigterm.watch().listen((signal) {
      print('');
      print('Received SIGTERM signal, shutting down gracefully...');
      _triggerShutdown();
    });

    // Handle SIGINT (Ctrl+C)
    _sigintSubscription = ProcessSignal.sigint.watch().listen((signal) {
      print('');
      print('Received SIGINT signal (Ctrl+C), shutting down gracefully...');
      _triggerShutdown();
    });
  }

  /// Cancel signal handlers to allow clean exit
  Future<void> _cancelSignalHandlers() async {
    await _sigtermSubscription?.cancel();
    await _sigintSubscription?.cancel();
    _sigtermSubscription = null;
    _sigintSubscription = null;
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
      _httpServer.libraryManager.scanMusicFolder(musicPath);
      print('[ServerRunner] ✓ Library scan initiated');

      return true;
    } catch (e) {
      print('[ServerRunner] ERROR starting scan: $e');
      return false;
    }
  }

  /// Setup callback: Get scan status
  Future<Map<String, dynamic>> _handleGetScanStatus() async {
    final isScanning = _httpServer.libraryManager.isScanning;
    final library = _httpServer.libraryManager.library;

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

  /// Detect if running on a Raspberry Pi.
  ///
  /// Checks for Linux ARM architecture and Pi-specific indicators.
  bool _isRaspberryPi() {
    if (!Platform.isLinux) return false;

    // Check for ARM architecture (common on Pi)
    final arch = Platform.version.toLowerCase();
    final isArm = arch.contains('arm') || arch.contains('aarch64');

    if (!isArm) return false;

    final model = _getRaspberryPiModel();
    if (model != null) {
      return true;
    }

    // If we're on Linux ARM but can't confirm Pi, assume it might be
    // (conservative approach for low-power ARM devices)
    return true;
  }

  bool _isRaspberryPi5() {
    final model = _getRaspberryPiModel();
    return model != null && model.contains('raspberry pi 5');
  }

  String? _getRaspberryPiModel() {
    if (!Platform.isLinux) return null;

    // Check for Pi model file first
    try {
      final modelFile = File('/proc/device-tree/model');
      if (modelFile.existsSync()) {
        final model = modelFile.readAsStringSync().toLowerCase();
        if (model.contains('raspberry')) {
          return model;
        }
      }

      final cpuInfo = File('/proc/cpuinfo');
      if (cpuInfo.existsSync()) {
        final content = cpuInfo.readAsStringSync().toLowerCase();
        if (content.contains('raspberry') || content.contains('bcm')) {
          return content;
        }
      }
    } catch (_) {
      // Ignore file read errors
    }

    return null;
  }

  // ============================================================================
  // DOWNLOAD LIMITS (PLATFORM + STORAGE AWARE)
  // ============================================================================

  Future<StorageType> _detectStorageType(String? targetPath) async {
    if (!Platform.isLinux || targetPath == null || targetPath.isEmpty) {
      return StorageType.unknown;
    }

    final mountsFile = File('/proc/mounts');
    if (!await mountsFile.exists()) {
      return StorageType.unknown;
    }

    try {
      final lines = await mountsFile.readAsLines();
      String? bestMountPoint;
      String? bestDevice;

      for (final line in lines) {
        final parts = line.split(' ');
        if (parts.length < 2) continue;
        final device = parts[0];
        final mountPoint = parts[1];

        if (targetPath.startsWith(mountPoint)) {
          if (bestMountPoint == null ||
              mountPoint.length > bestMountPoint.length) {
            bestMountPoint = mountPoint;
            bestDevice = device;
          }
        }
      }

      if (bestDevice == null) {
        return StorageType.unknown;
      }

      final device = bestDevice.toLowerCase();
      if (device.contains('mmcblk')) {
        return StorageType.microSd;
      }
      if (device.contains('nvme') || device.contains('/dev/sd')) {
        return StorageType.fastExternal;
      }
    } catch (_) {
      // Ignore mount parsing errors
    }

    return StorageType.unknown;
  }

  _DownloadLimits _selectDownloadLimits({
    required bool isPi,
    required bool isPi5,
    required StorageType storageType,
  }) {
    if (!isPi && Platform.isMacOS) {
      return const _DownloadLimits(
        maxConcurrent: 30,
        maxQueue: 400,
        maxConcurrentPerUser: 10,
        maxQueuePerUser: 200,
      );
    }

    if (!isPi) {
      return const _DownloadLimits(
        maxConcurrent: 10,
        maxQueue: 120,
        maxConcurrentPerUser: 3,
        maxQueuePerUser: 50,
      );
    }

    if (storageType == StorageType.fastExternal) {
      return const _DownloadLimits(
        maxConcurrent: 6,
        maxQueue: 80,
        maxConcurrentPerUser: 4,
        maxQueuePerUser: 30,
      );
    }

    if (isPi5) {
      return const _DownloadLimits(
        maxConcurrent: 4,
        maxQueue: 50,
        maxConcurrentPerUser: 4,
        maxQueuePerUser: 20,
      );
    }

    // Default for Pi 3/4 + microSD or unknown storage — allow four concurrent
    // original/high-quality downloads per user (mostly I/O, not transcode).
    return const _DownloadLimits(
      maxConcurrent: 4,
      maxQueue: 50,
      maxConcurrentPerUser: 4,
      maxQueuePerUser: 20,
    );
  }

  /// Handle transition from foreground setup mode to background daemon mode
  Future<Map<String, dynamic>> _handleTransitionToBackground() async {
    print('[ServerRunner] Transitioning to background mode...');

    try {
      // IMPORTANT: Stop HTTP server FIRST to release the port
      // This allows the background process to bind immediately without retries
      print('[ServerRunner] Stopping HTTP server to release port...');
      await _httpServer.stop();
      print('[ServerRunner] Port released');

      // Spawn background process with --server-mode flag
      final pid = await _daemonService.startServerInBackground([
        '--server-mode',
        '--port',
        _serverPort.toString(),
      ]);

      if (pid == null) {
        print('[ServerRunner] ERROR: Failed to spawn background process');
        // Can't return response since server is stopped, just exit with error
        await _cancelSignalHandlers();
        exit(1);
      }

      // Save server state for status command
      await _daemonService.saveServerState({
        'port': _serverPort,
        'pid': pid,
        'started_at': DateTime.now().toIso8601String(),
      });

      print('[ServerRunner] Background process spawned with PID: $pid');
      print('');
      print('═══════════════════════════════════════════════════════');
      print('  Setup complete! Server is now running in background.');
      print('');
      print('  You can safely close this terminal window.');
      print('');
      print('  To check status:  ./ariami_cli status');
      print('  To stop server:   ./ariami_cli stop');
      print('═══════════════════════════════════════════════════════');
      print('');

      // Cancel signal handlers to allow clean exit (they keep the isolate alive)
      await _cancelSignalHandlers();

      // Exit immediately - background is now running
      // NOTE: On Linux/Raspberry Pi, Dart's Process.run() may not return immediately
      // due to file descriptor inheritance. The user can safely close the terminal.
      exit(0);
    } catch (e) {
      print('[ServerRunner] Transition error: $e');
      // Can't return response, just exit with error
      await _cancelSignalHandlers();
      exit(1);
    }
  }
}

enum StorageType { microSd, fastExternal, unknown }

enum StorageProfile { microSd, externalFast, unknown }

StorageProfile selectStorageProfile({
  required bool isPi,
  required StorageType musicStorageType,
  required StorageType stateStorageType,
  String? override,
}) {
  final normalized = override?.trim().toLowerCase();
  if (normalized != null && normalized.isNotEmpty) {
    switch (normalized) {
      case 'microsd':
      case 'micro_sd':
      case 'micro-sd':
      case 'sd':
        return StorageProfile.microSd;
      case 'externalfast':
      case 'external_fast':
      case 'external-fast':
      case 'ssd':
      case 'fast':
        return StorageProfile.externalFast;
      case 'unknown':
      case 'auto':
        break;
      default:
        print(
            'Unknown ARIAMI_STORAGE_PROFILE="$override"; using auto detection.');
    }
  }

  if (!isPi) return StorageProfile.unknown;
  if (stateStorageType == StorageType.microSd ||
      musicStorageType == StorageType.microSd) {
    return StorageProfile.microSd;
  }
  if (stateStorageType == StorageType.fastExternal &&
      musicStorageType == StorageType.fastExternal) {
    return StorageProfile.externalFast;
  }
  return StorageProfile.unknown;
}

CachePolicy selectCachePolicy({
  required bool isPi,
  required bool isPi5,
  required StorageProfile storageProfile,
}) {
  if (!isPi && (Platform.isMacOS || Platform.isWindows)) {
    return const CachePolicy(
      transcodeCacheSizeMB: 4096,
      artworkCacheSizeMB: 256,
      transcodeIndexPersistInterval: Duration(seconds: 30),
      touchArtworkOnCacheHit: true,
      artworkTouchThrottle: Duration.zero,
    );
  }

  if (!isPi) {
    return const CachePolicy(
      transcodeCacheSizeMB: 2048,
      artworkCacheSizeMB: 256,
      transcodeIndexPersistInterval: Duration(seconds: 30),
      touchArtworkOnCacheHit: true,
      artworkTouchThrottle: Duration.zero,
    );
  }

  if (storageProfile == StorageProfile.externalFast) {
    return CachePolicy(
      transcodeCacheSizeMB: isPi5 ? 2048 : 1024,
      artworkCacheSizeMB: 256,
      transcodeIndexPersistInterval: const Duration(seconds: 30),
      touchArtworkOnCacheHit: true,
      artworkTouchThrottle: Duration.zero,
    );
  }

  return const CachePolicy(
    transcodeCacheSizeMB: 384,
    artworkCacheSizeMB: 96,
    transcodeIndexPersistInterval: Duration(minutes: 5),
    touchArtworkOnCacheHit: false,
    artworkTouchThrottle: Duration(minutes: 30),
  );
}

class CachePolicy {
  final int transcodeCacheSizeMB;
  final int artworkCacheSizeMB;
  final Duration transcodeIndexPersistInterval;
  final bool touchArtworkOnCacheHit;
  final Duration artworkTouchThrottle;

  const CachePolicy({
    required this.transcodeCacheSizeMB,
    required this.artworkCacheSizeMB,
    required this.transcodeIndexPersistInterval,
    required this.touchArtworkOnCacheHit,
    required this.artworkTouchThrottle,
  });
}

class _DownloadLimits {
  final int maxConcurrent;
  final int maxQueue;
  final int maxConcurrentPerUser;
  final int maxQueuePerUser;

  const _DownloadLimits({
    required this.maxConcurrent,
    required this.maxQueue,
    required this.maxConcurrentPerUser,
    required this.maxQueuePerUser,
  });
}
