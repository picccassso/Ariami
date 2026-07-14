import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/connection_service.dart';
import '../download/download_manager.dart';
import '../library/library_read_facade.dart';
import '../stats/streaming_stats_service.dart';

/// One-time repair for records written before album titles were resolved from
/// the normalized album ID. Remove this migration after the next core update
/// has shipped with the permanent metadata fix.
class AlbumMetadataRepairMigration {
  static const String _completedKeyPrefix =
      'migration_album_metadata_repair_v2_completed';

  final ConnectionService _connection = ConnectionService();
  final DownloadManager _downloads = DownloadManager();
  final StreamingStatsService _stats = StreamingStatsService();

  Future<bool> run({LibraryReadBundle? library}) async {
    final preferences = await SharedPreferences.getInstance();
    final completedKey = _completionKey();
    if (preferences.getBool(completedKey) == true) return false;

    try {
      final resolvedLibrary =
          library ?? await _connection.libraryReadFacade.getLibraryBundle();
      if (resolvedLibrary.isPartialRead ||
          resolvedLibrary.syncHealth?.hasSyncFailure == true ||
          (resolvedLibrary.albums.isEmpty && resolvedLibrary.songs.isEmpty)) {
        // Do not consume the migration on a first launch before the library
        // bootstrap has produced any catalog data.
        return false;
      }

      // LibraryController and the app shell warm stats independently during
      // startup. Await the shared idempotent initializer here so the migration
      // cannot record completion while the stats service is still empty.
      await _stats.initialize();
      await _stats.remapStaleStatIdsFromLibrary(
        resolvedLibrary.songs,
        libraryAlbums: resolvedLibrary.albums,
      );
      final repairedDownloads = await _downloads.refreshDownloadAlbumMetadata(
        libraryAlbums: resolvedLibrary.albums,
        librarySongs: resolvedLibrary.songs,
      );

      await preferences.setBool(completedKey, true);
      print(
        '[AlbumMetadataRepairMigration] Completed; repaired '
        '$repairedDownloads download record(s)',
      );
      return true;
    } catch (error) {
      // Leave the marker unset so a transient offline/bootstrap failure can
      // retry automatically on the next launch.
      print('[AlbumMetadataRepairMigration] Deferred: $error');
      return false;
    }
  }

  String _completionKey() {
    final info = _connection.apiClient?.serverInfo ?? _connection.serverInfo;
    final server = info?.baseUrl ?? _connection.apiClient?.baseUrl ?? 'offline';
    final user = _connection.userId?.trim();
    final scope = '$server|${user?.isNotEmpty == true ? user : 'legacy'}';
    final encoded = base64Url.encode(utf8.encode(scope));
    return '${_completedKeyPrefix}_$encoded';
  }
}
