import 'dart:convert';

import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/import_export_service.dart';
import 'package:ariami_mobile/services/library/library_pin_storage.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:ariami_mobile/services/stats/streaming_stats_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_support/private_sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const packageInfoChannel =
      MethodChannel('dev.fluttercommunity.plus/package_info');
  const filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
    StandardMethodCodec(),
  );

  void setMockMethodCallHandler(
    MethodChannel channel,
    Future<Object?>? Function(MethodCall call)? handler,
  ) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrivateSqfliteFfi('ariami_import_export_');

    setMockMethodCallHandler(packageInfoChannel, (MethodCall call) async {
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
    setMockMethodCallHandler(packageInfoChannel, null);
    setMockMethodCallHandler(filePickerChannel, null);
  });

  group('ImportExportService backup roundtrip', () {
    late ImportExportService importExportService;
    late PlaylistService playlistService;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      importExportService = ImportExportService();
      playlistService = PlaylistService();
      await playlistService.clearAllPlaylistData();
      setMockMethodCallHandler(filePickerChannel, null);
    });

    test('v4 backup roundtrip restores server-import state without duplicates',
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

      expect(backup['dataVersion'], 4);
      expect(backup['schemaVersion'], 4);
      expect(backup['exportVersion'], 4);
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
        playlistService
            .getServerPlaylistId(playlistService.playlists.single.id),
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

    test('pins export and repeated import remain idempotent', () async {
      await LibraryPinStorage.saveForUser(
        null,
        <String>{'album:album-a', 'playlist:playlist-a'},
      );
      final backup = await importExportService.buildBackupData();
      expect(backup['pinnedItems'], hasLength(2));

      await LibraryPinStorage.saveForUser(null, <String>{});
      final first = await importExportService.importBackupData(
        backup,
        ImportMode.merge,
      );
      final second = await importExportService.importBackupData(
        backup,
        ImportMode.merge,
      );

      expect(first.success, isTrue);
      expect(second.success, isTrue);
      expect(
        await LibraryPinStorage.loadForUser(null),
        <String>{'album:album-a', 'playlist:playlist-a'},
      );
    });

    test('importData reads picker bytes when no filesystem path is available',
        () async {
      final backup = <String, dynamic>{
        'dataVersion': 3,
        'playlists': <dynamic>[],
        'stats': <dynamic>[],
      };
      final backupBytes = Uint8List.fromList(utf8.encode(jsonEncode(backup)));
      final pickerCalls = <MethodCall>[];

      setMockMethodCallHandler(filePickerChannel, (MethodCall call) async {
        pickerCalls.add(call);
        return [
          {
            'path': null,
            'name': 'ariami_backup.json',
            'size': backupBytes.length,
            'bytes': backupBytes,
          },
        ];
      });

      final result = await importExportService.importData(ImportMode.merge);

      expect(result.success, isTrue);
      expect(importExportService.lastImportTime, isNotNull);
      expect(pickerCalls, hasLength(1));
      expect(pickerCalls.single.method, 'custom');
      expect(
        pickerCalls.single.arguments,
        containsPair('allowMultipleSelection', false),
      );
      expect(pickerCalls.single.arguments, containsPair('withData', true));
    });

    test('legacy v1 backup restores matching listening stats', () async {
      final statsService = StreamingStatsService();
      addTearDown(statsService.resetAllStats);
      await statsService.resetAllStats();

      final legacyBackup = <String, dynamic>{
        // v1 backups did not include dataVersion or server-import fields.
        'playlists': <dynamic>[],
        'stats': <dynamic>[
          <String, dynamic>{
            'songId': 'matching-song-id',
            'playCount': 42,
            'totalSeconds': 7200,
            'firstPlayed': '2025-01-02T03:04:05.000Z',
            'lastPlayed': '2025-06-07T08:09:10.000Z',
            'songTitle': 'Still Here',
            'songArtist': 'The Backups',
            'albumId': 'matching-album-id',
            'album': 'Old Saves',
            'albumArtist': 'The Backups',
          },
        ],
      };

      final result = await importExportService.importBackupData(
        legacyBackup,
        ImportMode.replace,
      );

      expect(result.success, isTrue);
      expect(result.statsImported, 1);

      final restored = statsService.getLocalDeviceStats();
      expect(restored, hasLength(1));
      expect(restored.single.songId, 'matching-song-id');
      expect(restored.single.playCount, 42);
      expect(restored.single.totalTime, const Duration(hours: 2));
      expect(restored.single.songTitle, 'Still Here');
      expect(restored.single.songArtist, 'The Backups');
    });

    test('exportData records last export after native save completes',
        () async {
      final pickerCalls = <MethodCall>[];

      setMockMethodCallHandler(filePickerChannel, (MethodCall call) async {
        pickerCalls.add(call);
        return '/document/primary:Download/ariami_backup.json';
      });

      final result = await importExportService.exportData();

      expect(result.success, isTrue);
      expect(result.filePath, '/document/primary:Download/ariami_backup.json');
      expect(importExportService.lastExportTime, isNotNull);
      expect(pickerCalls, hasLength(1));
      expect(pickerCalls.single.method, 'save');

      final arguments = pickerCalls.single.arguments as Map<Object?, Object?>;
      expect(arguments['fileName'], startsWith('ariami_backup_'));
      expect(arguments['fileName'], endsWith('.json'));
      expect(arguments['fileType'], 'custom');
      expect(arguments['allowedExtensions'], ['json']);

      final exportedBytes = arguments['bytes']! as Uint8List;
      final exportedJson =
          jsonDecode(utf8.decode(exportedBytes)) as Map<String, dynamic>;
      expect(exportedJson['dataVersion'], 4);
    });
  });
}
