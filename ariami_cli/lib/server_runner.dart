import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'package:path/path.dart' as p;

import 'services/cli_state_service.dart';
import 'services/cli_status_info.dart';
import 'services/cli_tailscale_service.dart';
import 'services/container_environment.dart';
import 'services/daemon_service.dart';
import 'services/server_daemon_transition_service.dart';
import 'services/server_feature_flag_service.dart';
import 'services/server_http_ready_notifier.dart';
import 'services/server_lifecycle_service.dart';
import 'services/server_media_services_configurator.dart';
import 'services/server_runtime_policy.dart';
import 'services/server_setup_callbacks.dart';
import 'services/startup_summary.dart';
import 'services/web_assets_resolver.dart';

export 'services/server_http_ready_notifier.dart';
export 'services/server_runtime_policy.dart';

Future<Map<String, dynamic>> buildServerModeTransitionResponse() async {
  return {
    'success': true,
    'alreadyInForeground': true,
    'message': 'Ariami is already running in the foreground for container or '
        'supervised mode. Setup can continue here.',
  };
}

/// Runs the Ariami CLI server in foreground setup or background daemon mode.
class ServerRunner {
  ServerRunner() {
    _setupCallbacks = ServerSetupCallbacks(
      httpServer: _httpServer,
      stateService: _stateService,
    );
    _lifecycleService = ServerLifecycleService(httpServer: _httpServer);
    _daemonTransitionService = ServerDaemonTransitionService(
      httpServer: _httpServer,
      daemonService: _daemonService,
      lifecycleService: _lifecycleService,
    );
    _mediaServicesConfigurator =
        ServerMediaServicesConfigurator(httpServer: _httpServer);
  }

  final AriamiHttpServer _httpServer = AriamiHttpServer();
  final CliStateService _stateService = CliStateService();
  final CliTailscaleService _tailscaleService = CliTailscaleService();
  final DaemonService _daemonService = DaemonService();
  final WebAssetsResolver _webAssetsResolver = WebAssetsResolver();
  final ContainerEnvironment _containerEnvironment = ContainerEnvironment();
  final ServerFeatureFlagService _featureFlagService =
      ServerFeatureFlagService();
  final ServerRuntimePolicy _runtimePolicy = ServerRuntimePolicy();

  late final ServerSetupCallbacks _setupCallbacks;
  late final ServerLifecycleService _lifecycleService;
  late final ServerDaemonTransitionService _daemonTransitionService;
  late final ServerMediaServicesConfigurator _mediaServicesConfigurator;

  int _serverPort = 8080;

  /// Run the Ariami server.
  ///
  /// - [port]: Preferred server port (default: 8080)
  /// - [allowPortFallback]: When true, scan 8080-8099 if preferred port is busy
  /// - [isSetupMode]: If true, server runs for setup without library scanning
  /// - [isServerMode]: If true, running as background daemon (write own PID)
  /// - [verbose]: If true, print stack traces for fatal startup errors
  /// - [onHttpServerReady]: Called after the HTTP server is listening
  Future<void> run({
    required int port,
    required bool isSetupMode,
    bool isServerMode = false,
    bool allowPortFallback = true,
    bool verbose = false,
    Future<void> Function(int port)? onHttpServerReady,
  }) async {
    print('Ariami Server starting...');
    _serverPort = port;

    try {
      final featureFlags = _featureFlagService.loadFromEnvironment();
      _featureFlagService.validateOrThrow(featureFlags);
      _httpServer.setFeatureFlags(featureFlags);

      await _stateService.ensureConfigDir();

      // Pre-auth account picker for TV sign-in. On by default; the web
      // dashboard's privacy switch persists an explicit off in config.json,
      // and the env flag can force it back on for such a config.
      _httpServer.setPublicUserPickerEnabled(
        await _stateService.getPublicUserPickerEnabled() ||
            _featureFlagService.loadPublicUserPickerFromEnvironment(),
      );
      _httpServer.setPublicUserPickerPersistCallback(
        (enabled) => _stateService.setPublicUserPickerEnabled(enabled),
      );
      _configureMetadataCache(featureFlags);

      final isPi = _runtimePolicy.isRaspberryPi();
      final isPi5 = isPi && _runtimePolicy.isRaspberryPi5();

      _lifecycleService.setupSignalHandlers();

      if (isServerMode) {
        await _daemonService.saveServerPid(pid);
        print('Server PID: $pid');
      }

      await _configureWebAssets();
      _configureNetworkCallbacks();
      _setupCallbacks.register();

      if (isSetupMode) {
        _httpServer.setTransitionToBackgroundCallback(
          () => _daemonTransitionService.transitionToBackground(
            serverPort: _serverPort,
          ),
        );
      } else if (isServerMode) {
        _httpServer.setTransitionToBackgroundCallback(
          buildServerModeTransitionResponse,
        );
      }

      await _httpServer.initializeAuth(
        usersFilePath: CliStateService.getUsersFilePath(),
        sessionsFilePath: CliStateService.getSessionsFilePath(),
      );

      final cachePolicy = await _configureRuntimeLimits(
        isPi: isPi,
        isPi5: isPi5,
      );

      final advertisedIp = await _startHttpServer(
        port: port,
        allowPortFallback: allowPortFallback,
      );
      print('✓ HTTP server started successfully');
      print('✓ Server accessible at: http://$advertisedIp:$_serverPort');

      await notifyHttpServerReady(onHttpServerReady, _serverPort);

      await _mediaServicesConfigurator.configure(
        isPi: isPi,
        cachePolicy: cachePolicy,
        transcodeSlotsSnapshot:
            await _setupCallbacks.getTranscodeSlotsSnapshot(),
      );

      if (!isSetupMode) {
        final canStartScan = await _warnIfMissingMusicFolder();
        if (canStartScan) {
          await _setupCallbacks.startInitialScanIfConfigured();
        }
      }

      await _printRunningBanner(
        isSetupMode: isSetupMode,
        isServerMode: isServerMode,
      );

      await _lifecycleService.waitForShutdown();
      await _lifecycleService.shutdown();
    } catch (e, stackTrace) {
      stderr.writeln('');
      stderr.writeln('ERROR: Ariami server failed to start');
      final cause = _formatStartupError(e);
      if (cause.isNotEmpty) {
        stderr.writeln(cause);
      }
      if (verbose) {
        stderr.writeln('Stack trace: $stackTrace');
      }
      stderr.writeln('');

      try {
        await _httpServer.stop();
      } catch (_) {
        // Ignore cleanup errors.
      }

      rethrow;
    }
  }

  void _configureMetadataCache(AriamiFeatureFlags featureFlags) {
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
  }

  Future<void> _configureWebAssets() async {
    final webAssets = await _webAssetsResolver.resolve();
    if (!webAssets.found) {
      _webAssetsResolver.printNotFoundError(webAssets);
      throw StateError('Web UI assets not found');
    }
    _httpServer.setWebAssetsPath(webAssets.path!);
  }

  void _configureNetworkCallbacks() {
    _httpServer.setTailscaleStatusCallback(() => _tailscaleService.getStatus());
    if (_containerEnvironment.hasAnyAdvertisedOverride) {
      return;
    }
    _httpServer.setEndpointDiscoveryCallback(() async {
      final ts = await _tailscaleService.getTailscaleIp();
      final lan = await _tailscaleService.getLanIp();
      return NetworkEndpoints(tailscaleIp: ts, lanIp: lan);
    });
  }

  Future<CachePolicy> _configureRuntimeLimits({
    required bool isPi,
    required bool isPi5,
  }) async {
    final musicPath = await _stateService.getMusicFolderPath();
    final musicStorageType = isPi
        ? await _runtimePolicy.detectStorageType(musicPath)
        : StorageType.unknown;
    final stateStorageType = isPi
        ? await _runtimePolicy.detectStorageType(CliStateService.getConfigDir())
        : StorageType.unknown;
    final storageProfile = selectStorageProfile(
      isPi: isPi,
      musicStorageType: musicStorageType,
      stateStorageType: stateStorageType,
      override: Platform.environment['ARIAMI_STORAGE_PROFILE'],
    );
    final limits = _runtimePolicy.selectDownloadLimits(
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
    return cachePolicy;
  }

  Future<String> _startHttpServer({
    required int port,
    required bool allowPortFallback,
  }) async {
    final bindHost = await _stateService.getBindHost();
    final endpoints = await _resolveAdvertisedEndpoints(bindHost);
    final savedPort = await _stateService.getServerPort();

    print('Starting HTTP server on $bindHost (preferred port: $port)...');
    _serverPort = await _httpServer.startWithPortFallback(
      advertisedIp: endpoints.advertisedIp,
      tailscaleIp: endpoints.tailscaleIp,
      lanIp: endpoints.lanIp,
      bindAddress: bindHost,
      preferredPort: port,
      savedPort: savedPort,
      allowFallback: allowPortFallback,
    );
    await _stateService.setServerPort(_serverPort);

    final attemptedPort =
        _httpServer.getServerInfo()['attemptedPort'] as int? ?? port;
    final fallbackMessage = ServerPortPolicy.formatFallbackMessage(
      attemptedPort: attemptedPort,
      actualPort: _serverPort,
    );
    if (fallbackMessage != null) {
      print('');
      print(fallbackMessage);
      print(
          'Rescan the QR code if you previously connected on port $attemptedPort.');
      print('');
    }

    return endpoints.advertisedIp;
  }

  Future<bool> _warnIfMissingMusicFolder() async {
    final musicPath = await _stateService.getMusicFolderPath();
    if (musicPath == null || musicPath.isEmpty) {
      return true;
    }

    if (!await Directory(musicPath).exists()) {
      print(
        'Warning: configured music folder $musicPath does not exist. '
        'Fix the path in the dashboard or reattach the drive.',
      );
      return false;
    }

    return true;
  }

  Future<void> _printRunningBanner({
    required bool isSetupMode,
    required bool isServerMode,
  }) async {
    final bindHost = await _stateService.getBindHost();
    final endpoints = await _resolveAdvertisedEndpoints(bindHost);
    final musicDir = await _stateService.getMusicFolderPath();
    final musicDirExists = musicDir != null &&
        musicDir.isNotEmpty &&
        await Directory(musicDir).exists();
    final auth = await readAuthSummary();
    final setupComplete = !isSetupMode && await _stateService.isSetupComplete();

    print('');
    for (final line in StartupSummary.buildBanner(
      version: kAriamiVersion,
      modeLabel: isServerMode ? 'background' : 'foreground',
      port: _serverPort,
      bindHost: bindHost,
      lanIp: endpoints.lanIp,
      tailscaleIp: endpoints.tailscaleIp,
      dataDir: CliStateService.getConfigDir(),
      musicDir: musicDir,
      musicDirExists: musicDirExists,
      accountCount: auth.accountCount,
      hasOwnerAccount: auth.hasOwnerAccount,
      setupComplete: setupComplete,
      pid: isServerMode ? pid : null,
    )) {
      print(line);
    }
    print('');
  }

  Future<_AdvertisedEndpoints> _resolveAdvertisedEndpoints(
      String bindHost) async {
    final detectedTailscaleIp = await _tailscaleService.getTailscaleIp();
    final detectedLanIp = await _tailscaleService.getLanIp();
    final genericOverride = _containerEnvironment.advertisedHostOverride;
    final lanOverride = _containerEnvironment.advertisedLanHostOverride;
    final tailscaleOverride =
        _containerEnvironment.advertisedTailscaleHostOverride;

    final effectiveTailscaleIp = tailscaleOverride ?? detectedTailscaleIp;
    final effectiveLanIp = lanOverride ?? genericOverride ?? detectedLanIp;
    final advertisedIp = _isLocalBindHost(bindHost)
        ? 'localhost'
        : genericOverride ??
            effectiveTailscaleIp ??
            effectiveLanIp ??
            'localhost';

    return _AdvertisedEndpoints(
      advertisedIp: advertisedIp,
      lanIp: effectiveLanIp,
      tailscaleIp: effectiveTailscaleIp,
    );
  }

  String _formatStartupError(Object error) {
    if (error is PortBindingException) {
      return error.toString();
    }

    if (error is StateError && error.message == 'Web UI assets not found') {
      return 'Web UI assets were not found. See the guidance above.';
    }

    if (error is FileSystemException && _isPermissionDenied(error)) {
      return 'Permission denied while accessing Ariami data. Check permissions '
          'on ${CliStateService.getConfigDir()} and the ARIAMI_DATA_DIR '
          'environment variable.';
    }

    return 'Cause: $error';
  }

  bool _isPermissionDenied(FileSystemException error) {
    final osError = error.osError;
    if (osError != null && osError.errorCode == 13) {
      return true;
    }
    return error.message.toLowerCase().contains('permission denied');
  }

  bool _isLocalBindHost(String bindHost) {
    final normalized = bindHost.trim().toLowerCase();
    return normalized == '127.0.0.1' || normalized == 'localhost';
  }
}

class _AdvertisedEndpoints {
  const _AdvertisedEndpoints({
    required this.advertisedIp,
    required this.lanIp,
    required this.tailscaleIp,
  });

  final String advertisedIp;
  final String? lanIp;
  final String? tailscaleIp;
}
