import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/library_sync_database.dart';
import '../services/api/connection_service.dart';
import '../services/audio/playback_state_manager.dart';
import '../services/cache/cache_manager.dart';
import '../services/color_extraction_service.dart';
import '../services/download/download_manager.dart';
import '../services/offline/offline_playback_service.dart';
import '../services/offline/offline_copy_service.dart';
import '../services/offline/sync_service.dart';
import '../services/playback_manager.dart';
import '../services/playlist_service.dart';
import '../services/profile_image_service.dart';
import '../services/quality/quality_settings_service.dart';
import '../services/stats/account_stats_service.dart';
import '../services/stats/streaming_stats_service.dart';
import '../services/theme_service.dart';
import 'shared_preferences_cache.dart';

/// Clears all local user data for a full disconnect / app reset.
Future<void> clearAllLocalUserData({String? userId}) async {
  Object? firstError;
  StackTrace? firstStackTrace;

  Future<void> clearStep(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }

  // Continue through every reset step if one local store is unavailable. The
  // server unlink is first so a partial local-cleanup failure can never leave
  // credentials or a saved endpoint behind.
  await clearStep(() => ConnectionService().disconnectAndForgetServer());
  await clearStep(() => PlaybackManager().stopAndClearQueue());
  await clearStep(() => DownloadManager().clearAllDownloads());
  await clearStep(() => CacheManager().clearAllCache());
  await clearStep(() async {
    final libraryDatabase = await LibrarySyncDatabase.create();
    await libraryDatabase.clearAllData();
  });
  await clearStep(() => PlaylistService().clearAllPlaylistData());
  await clearStep(() => SyncService().clearPendingActions());
  await clearStep(() => StreamingStatsService().resetAllStats());
  // Local wipe only: the account's stats stay on the server for other devices.
  await clearStep(() => AccountStatsService().clearLocalOnly());
  await clearStep(() => ProfileImageService().clear());
  await clearStep(_deletePlaylistImagesDirectory);
  await clearStep(() async {
    final playbackStateManager = PlaybackStateManager();
    await playbackStateManager.clearState();
    await playbackStateManager.clearCompletePlaybackState();
    if (userId != null && userId.trim().isNotEmpty) {
      await playbackStateManager.clearCompletePlaybackState(userId: userId);
    }
  });
  await clearStep(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await reloadSharedPrefs();
  });
  await clearStep(() async {
    ThemeService().resetToDefaults();
    ColorExtractionService().clearCache();
    QualitySettingsService().resetToDefaults();
    OfflinePlaybackService().resetToDefaults();
    OfflineCopyService().resetToDefaults();
    await ThemeService().setThemeSource(ThemeSource.darkNeutral);
  });

  if (firstError != null) {
    Error.throwWithStackTrace(firstError!, firstStackTrace!);
  }
}

Future<void> _deletePlaylistImagesDirectory() async {
  final appDir = await getApplicationDocumentsDirectory();
  final playlistImagesDir = Directory('${appDir.path}/playlist_images');
  if (await playlistImagesDir.exists()) {
    await playlistImagesDir.delete(recursive: true);
  }
}
