import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/feature_flags_loader.dart';
import 'desktop_state_service.dart';

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

  /// Feature flags, metadata cache path, catalog repository check, [setFeatureFlags].
  Future<void> configureLibraryCacheAndFeatureFlags(
      AriamiHttpServer httpServer) async {
    final featureFlags = loadFeatureFlagsFromEnvironment();
    validateFeatureFlagInvariantsOrThrow(featureFlags);

    final appDir = await getApplicationSupportDirectory();
    final cachePath = p.join(appDir.path, 'metadata_cache.json');
    httpServer.libraryManager.setCachePath(cachePath);

    if (featureFlags.enableV2Api &&
        httpServer.libraryManager.createCatalogRepository() == null) {
      throw StateError(
        'Invalid startup configuration: enableV2Api=true requires catalog '
        'repository availability. Failed to initialize catalog at $cachePath.',
      );
    }

    httpServer.setFeatureFlags(featureFlags);
  }

  /// Desktop transcoding and artwork caches (idempotent).
  Future<void> ensureTranscodingAndArtworkServices(
      AriamiHttpServer httpServer) async {
    final appDir = await getApplicationSupportDirectory();

    if (_transcodingService == null) {
      final transcodingCachePath = p.join(appDir.path, 'transcoded_cache');
      _transcodingService = TranscodingService(
        cacheDirectory: transcodingCachePath,
        maxCacheSizeMB: 4096,
        maxConcurrency: 2,
        maxDownloadConcurrency: Platform.isMacOS ? 10 : 6,
        sonicLibraryPath: _resolveBundledSonicLibraryPath(),
      );
      httpServer.setTranscodingService(_transcodingService!);
      print(
          '[ServerInit] Transcoding service initialized at: $transcodingCachePath');

      _transcodingService!.isSonicAvailable().then((available) {
        if (!available) {
          print(
              '[ServerInit] Warning: Sonic not available - transcoding will be disabled');
        }
      });
    }

    if (_artworkService == null) {
      final artworkCachePath = p.join(appDir.path, 'artwork_cache');
      _artworkService = ArtworkService(
        cacheDirectory: artworkCachePath,
        maxCacheSizeMB: 256,
      );
      httpServer.setArtworkService(_artworkService!);
      print('[ServerInit] Artwork service initialized at: $artworkCachePath');
    }
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
  }

  static void applyDesktopDownloadLimits(AriamiHttpServer httpServer) {
    httpServer.setDownloadLimits(
      maxConcurrent: Platform.isMacOS ? 30 : 10,
      maxQueue: Platform.isMacOS ? 400 : 120,
      maxConcurrentPerUser: Platform.isMacOS ? 10 : 3,
      maxQueuePerUser: Platform.isMacOS ? 200 : 50,
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
