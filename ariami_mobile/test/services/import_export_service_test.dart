import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/import_export_service.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:ariami_mobile/services/stats/streaming_stats_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const packageInfoChannel =
      MethodChannel('dev.fluttercommunity.plus/package_info');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    packageInfoChannel.setMockMethodCallHandler((MethodCall call) async {
      if (call.method == 'getAll') {
        return <String, dynamic>{
          'appName': 'Ariami',
          'packageName': 'test',
          'version': '1.0.0',
          'buildNumber': '1',
        };
      }
      return null;
    });

    await ImportExportService().initialize();
    await StreamingStatsService().initialize();
  });

  tearDownAll(() {
    packageInfoChannel.setMockMethodCallHandler(null);
  });

  group('ImportExportService backup roundtrip', () {
    late ImportExportService importExportService;
    late PlaylistService playlistService;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      importExportService = ImportExportService();
      playlistService = PlaylistService();
      await playlistService.clearAllPlaylistData();
    });

    test('v3 backup roundtrip restores server-import state without duplicates',
        () async {
      final imported = await playlistService.importServerPlaylist(
        ServerPlaylist(
          id: 'server-1',
          name: 'Summer Vibes',
          songIds: const <String>['song-1'],
          songCount: 1,
        ),
        allSongs: const <SongModel>[],
      );

      final backup = await importExportService.buildBackupData();

      expect(backup['dataVersion'], 3);
      expect(backup['hiddenServerPlaylistIds'], ['server-1']);
      expect(
        backup['importedFromServer'],
        {imported.id: 'server-1'},
      );

      await playlistService.clearAllPlaylistData();

      final result = await importExportService.importBackupData(
        backup,
        ImportMode.merge,
      );

      expect(result.success, isTrue);
      expect(playlistService.playlists.length, 1);
      expect(playlistService.playlists.single.name, 'Summer Vibes');
      expect(playlistService.hiddenServerPlaylistIds, contains('server-1'));
      expect(
        playlistService.getServerPlaylistId(playlistService.playlists.single.id),
        'server-1',
      );

      final duplicateAttempt = await playlistService.importServerPlaylist(
        ServerPlaylist(
          id: 'server-1',
          name: 'Summer Vibes',
          songIds: const <String>['song-1'],
          songCount: 1,
        ),
        allSongs: const <SongModel>[],
      );

      expect(duplicateAttempt.id, playlistService.playlists.single.id);
      expect(playlistService.playlists.length, 1);
    });

    test('merge reimport on same device skips duplicate playlist by id',
        () async {
      await playlistService.importServerPlaylist(
        ServerPlaylist(
          id: 'server-1',
          name: 'Summer Vibes',
          songIds: const <String>['song-1'],
          songCount: 1,
        ),
        allSongs: const <SongModel>[],
      );

      final backup = await importExportService.buildBackupData();
      final result = await importExportService.importBackupData(
        backup,
        ImportMode.merge,
      );

      expect(result.success, isTrue);
      expect(result.playlistsImported, 0);
      expect(playlistService.playlists.length, 1);
      expect(playlistService.hiddenServerPlaylistIds, contains('server-1'));
    });
  });
}
