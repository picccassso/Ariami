import 'package:ariami_core/ariami_core.dart';
import 'package:path/path.dart' as p;

import 'cli_state_service.dart';
import 'server_runtime_policy.dart';

/// Creates the transcode and artwork services after the HTTP server is ready.
class ServerMediaServicesConfigurator {
  ServerMediaServicesConfigurator({required AriamiHttpServer httpServer})
      : _httpServer = httpServer;

  final AriamiHttpServer _httpServer;

  Future<void> configure({
    required bool isPi,
    required CachePolicy cachePolicy,
    required TranscodeSlotsSnapshot transcodeSlotsSnapshot,
  }) async {
    final transcodingCachePath =
        p.join(CliStateService.getConfigDir(), 'transcoded_cache');
    final maxConcurrency = transcodeSlotsSnapshot.effective;
    final maxDownloadConcurrency = transcodeSlotsSnapshot.effective;
    final maxCacheSizeMB = cachePolicy.transcodeCacheSizeMB;
    print('Transcode slots: $maxConcurrency '
        '(default ${transcodeSlotsSnapshot.defaultSlots}'
        '${transcodeSlotsSnapshot.isCustom ? ', custom override' : ''})');

    final transcodingService = TranscodingService(
      cacheDirectory: transcodingCachePath,
      maxCacheSizeMB: maxCacheSizeMB,
      maxConcurrency: maxConcurrency,
      maxDownloadConcurrency: maxDownloadConcurrency,
      transcodeTimeout: Duration(minutes: isPi ? 10 : 5),
      indexPersistInterval: cachePolicy.transcodeIndexPersistInterval,
    );
    _httpServer.setTranscodingService(transcodingService);
    print('Transcoding cache: $transcodingCachePath');
    print(
        'Transcoding limits: maxConcurrency=$maxConcurrency, maxDownloadConcurrency=$maxDownloadConcurrency');
    print('Transcoding cache policy: maxCacheSizeMB=$maxCacheSizeMB, '
        'indexPersistInterval=${cachePolicy.transcodeIndexPersistInterval.inSeconds}s');

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

    final sonicAvailable = await transcodingService.isSonicAvailable();
    if (sonicAvailable) {
      print('✓ Sonic available - audio transcoding enabled');
    } else {
      print(
          '⚠ Sonic not available - audio transcoding disabled (will serve original files)');
    }

    final artworkFfmpegAvailable = await artworkService.isFFmpegAvailable();
    if (artworkFfmpegAvailable) {
      print('✓ FFmpeg available - artwork thumbnails enabled');
    } else {
      print(
          '⚠ FFmpeg not found - artwork thumbnails disabled (original artwork only)');
    }
  }
}
