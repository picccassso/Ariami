import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/feature_flags_loader.dart';
import 'desktop_download_limits_service.dart';
import 'desktop_state_service.dart';
import 'desktop_tailscale_service.dart';
import 'desktop_transcode_slots_service.dart';

/// Result of starting the desktop HTTP listener with optional port fallback.
class DesktopServerStartResult {
  const DesktopServerStartResult({
    required this.port,
    this.fallbackMessage,
  });

  final int port;
  final String? fallbackMessage;
}

/// Shared desktop server configuration: feature flags, library cache, transcoding/artwork.
///
/// Holds process-wide transcoding/artwork instances (previously file-level globals).
class ServerInitializationService {
  factory ServerInitializationService() => _instance;
  ServerInitializationService._internal();
  static final ServerInitializationService _instance =
      ServerInitializationService._internal();

  TranscodingService? _transcodingService;
  ArtworkService? _artworkService;
  final DesktopTranscodeSlotsService _transcodeSlotsService =
      DesktopTranscodeSlotsService();

  /// Feature flags, metadata cache path, catalog repository check, [setFeatureFlags].
  Future<void> configureLibraryCacheAndFeatureFlags(
      AriamiHttpServer httpServer) async {
    final featureFlags = loadFeatureFlagsFromEnvironment();
    validateFeatureFlagInvariantsOrThrow(featureFlags);

    final appDir = await getApplicationSupportDirectory();
    final cachePath = p.join(appDir.path, 'metadata_cache.json');
    httpServer.libraryManager.setCachePath(cachePath);
    httpServer.setFeatureFlags(featureFlags);

    if (featureFlags.enableV2Api &&
        httpServer.libraryManager.createCatalogRepository() == null) {
      throw StateError(
        'Invalid startup configuration: enableV2Api=true requires catalog '
        'repository availability. Failed to initialize catalog at $cachePath.',
      );
    }
  }

  /// Desktop transcoding and artwork caches (idempotent).
  Future<void> ensureTranscodingAndArtworkServices(
      AriamiHttpServer httpServer) async {
    await _ensureTranscodingService(httpServer);
    await _ensureArtworkService(httpServer);
  }

  /// Rebuild the transcoding service with the latest slot configuration.
  Future<void> recreateTranscodingService(AriamiHttpServer httpServer) async {
    _transcodingService?.dispose();
    _transcodingService = null;
    await _ensureTranscodingService(httpServer);
  }

  Future<void> _ensureTranscodingService(AriamiHttpServer httpServer) async {
    if (_transcodingService != null) {
      return;
    }

    final appDir = await getApplicationSupportDirectory();
    final transcodingCachePath = p.join(appDir.path, 'transcoded_cache');
    final snapshot = await _transcodeSlotsService.getSnapshot();
    final slots = snapshot.effective;

    _transcodingService = TranscodingService(
      cacheDirectory: transcodingCachePath,
      maxCacheSizeMB: 4096,
      maxConcurrency: slots,
      maxDownloadConcurrency: slots,
      sonicLibraryPath: _resolveBundledSonicLibraryPath(),
    );
    httpServer.setTranscodingService(_transcodingService!);
    print(
        '[ServerInit] Transcoding service initialized at: $transcodingCachePath '
        '(slots=$slots, default=${snapshot.defaultSlots}'
        '${snapshot.isCustom ? ', custom override' : ''})');

    _transcodingService!.isSonicAvailable().then((available) {
      if (!available) {
        print(
            '[ServerInit] Warning: Sonic not available - transcoding will be disabled');
      }
    });
  }

  Future<void> _ensureArtworkService(AriamiHttpServer httpServer) async {
    if (_artworkService != null) {
      return;
    }

    final appDir = await getApplicationSupportDirectory();
    final artworkCachePath = p.join(appDir.path, 'artwork_cache');
    _artworkService = ArtworkService(
      cacheDirectory: artworkCachePath,
      maxCacheSizeMB: 256,
    );
    httpServer.setArtworkService(_artworkService!);
    print('[ServerInit] Artwork service initialized at: $artworkCachePath');
  }

  /// Multi-user auth file paths and [initializeAuth] on the server.
  static Future<void> initializeAuth(
    AriamiHttpServer httpServer,
    DesktopStateService stateService,
  ) async {
    await stateService.ensureAuthConfigDir();
    final usersFilePath = await stateService.getUsersFilePath();
    final sessionsFilePath = await stateService.getSessionsFilePath();
    await httpServer.initializeAuth(
      usersFilePath: usersFilePath,
      sessionsFilePath: sessionsFilePath,
    );

    // Re-apply the owner's saved account-picker choice; the server-side
    // setting is runtime-only and defaults to private. Changes made through
    // the admin endpoint persist through the same preference.
    httpServer.setPublicUserPickerEnabled(
      await stateService.isTvAccountPickerEnabled(),
    );
    httpServer.setPublicUserPickerPersistCallback(
      (enabled) => stateService.setTvAccountPickerEnabled(enabled),
    );
  }

  static Future<void> applyDesktopDownloadLimits(
      AriamiHttpServer httpServer) async {
    final downloadLimits = await DesktopDownloadLimitsService.resolve();
    httpServer.setDownloadLimits(
      maxConcurrent: downloadLimits.maxConcurrent,
      maxQueue: downloadLimits.maxQueue,
      maxConcurrentPerUser: downloadLimits.maxConcurrentPerUser,
      maxQueuePerUser: downloadLimits.maxQueuePerUser,
    );
  }

  /// Tailscale status API and periodic endpoint discovery for the HTTP server.
  static void configureNetworkDiscovery(
    AriamiHttpServer httpServer,
    DesktopTailscaleService tailscaleService,
  ) {
    httpServer.setTailscaleStatusCallback(() => tailscaleService.getStatus());
    httpServer.setEndpointDiscoveryCallback(() async {
      final ts = await tailscaleService.getTailscaleIp();
      final lan = await tailscaleService.getLanIp();
      return NetworkEndpoints(tailscaleIp: ts, lanIp: lan);
    });
  }

  /// Start the HTTP server with port fallback and persist the resolved port.
  static Future<DesktopServerStartResult> startListeningServer({
    required AriamiHttpServer httpServer,
    required DesktopStateService stateService,
    required String advertisedIp,
    String? tailscaleIp,
    String? lanIp,
  }) async {
    final savedPort = await stateService.getServerPort();
    final preferredPort = savedPort ?? ServerPortPolicy.defaultPort;

    final resolvedPort = await httpServer.startWithPortFallback(
      advertisedIp: advertisedIp,
      tailscaleIp: tailscaleIp,
      lanIp: lanIp,
      preferredPort: preferredPort,
      savedPort: savedPort,
      allowFallback: true,
    );

    await stateService.setServerPort(resolvedPort);

    final attemptedPort =
        httpServer.getServerInfo()['attemptedPort'] as int? ?? preferredPort;
    final fallbackMessage = ServerPortPolicy.formatFallbackMessage(
      attemptedPort: attemptedPort,
      actualPort: resolvedPort,
    );

    return DesktopServerStartResult(
      port: resolvedPort,
      fallbackMessage: fallbackMessage,
    );
  }

  String? _resolveBundledSonicLibraryPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    if (Platform.isMacOS) {
      final candidates = <String>[
        p.join(exeDir, '..', '..', '..', 'Frameworks',
            'libsonic_transcoder.dylib'),
        p.join(exeDir, '..', '..', 'Frameworks', 'libsonic_transcoder.dylib'),
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return candidate;
        }
      }
      return null;
    }

    if (Platform.isLinux) {
      final candidates = <String>[
        p.join(exeDir, 'lib', 'libsonic_transcoder.so'),
        p.join(exeDir, 'libsonic_transcoder.so'),
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return candidate;
        }
      }
      return null;
    }

    if (Platform.isWindows) {
      final candidate = p.join(exeDir, 'sonic_transcoder.dll');
      if (File(candidate).existsSync()) {
        return candidate;
      }
      return null;
    }

    return null;
  }
}
