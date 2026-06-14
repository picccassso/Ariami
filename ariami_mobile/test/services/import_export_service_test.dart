import 'dart:convert';

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
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

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
      expect(exportedJson['dataVersion'], 3);
    });
  });
}
