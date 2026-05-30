import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'package:path/path.dart' as p;

import 'services/cli_state_service.dart';
import 'services/cli_tailscale_service.dart';
import 'services/daemon_service.dart';
import 'services/server_daemon_transition_service.dart';
import 'services/server_feature_flag_service.dart';
import 'services/server_http_ready_notifier.dart';
import 'services/server_lifecycle_service.dart';
import 'services/server_media_services_configurator.dart';
import 'services/server_runtime_policy.dart';
import 'services/server_setup_callbacks.dart';
import 'services/web_assets_resolver.dart';

export 'services/server_http_ready_notifier.dart';
export 'services/server_runtime_policy.dart';

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
  /// - [onHttpServerReady]: Called after the HTTP server is listening
  Future<void> run({
    required int port,
    required bool isSetupMode,
    bool isServerMode = false,
    bool allowPortFallback = true,
    Future<void> Function(int port)? onHttpServerReady,
  }) async {
    print('Ariami Server starting...');
    _serverPort = port;

    try {
      final featureFlags = _featureFlagService.loadFromEnvironment();
      _featureFlagService.validateOrThrow(featureFlags);
      _httpServer.setFeatureFlags(featureFlags);

      await _stateService.ensureConfigDir();
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
        await _setupCallbacks.startInitialScanIfConfigured();
      }

      _printRunningBanner(isSetupMode: isSetupMode);

      await _lifecycleService.waitForShutdown();
      await _lifecycleService.shutdown();
    } catch (e, stackTrace) {
      print('');
      print('ERROR: Server failed to start');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      print('');

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
    final tailscaleIp = await _tailscaleService.getTailscaleIp();
    final lanIp = await _tailscaleService.getLanIp();
    final advertisedIp = tailscaleIp ?? lanIp ?? 'localhost';
    final savedPort = await _stateService.getServerPort();

    print('Starting HTTP server on 0.0.0.0 (preferred port: $port)...');
    _serverPort = await _httpServer.startWithPortFallback(
      advertisedIp: advertisedIp,
      tailscaleIp: tailscaleIp,
      lanIp: lanIp,
      bindAddress: '0.0.0.0',
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

    return advertisedIp;
  }

  void _printRunningBanner({required bool isSetupMode}) {
    print('');
    print('═══════════════════════════════════════════════════════');
    print('  Ariami Server is running');
    print('  URL: http://localhost:$_serverPort');
    if (isSetupMode) {
      print('  Mode: Setup (first-time configuration)');
    } else {
      print('  Mode: Normal operation');
    }
    print('═══════════════════════════════════════════════════════');
    print('');
  }
}
