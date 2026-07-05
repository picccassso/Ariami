import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_mobile/models/download_task.dart';
import 'package:ariami_mobile/services/download/download_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression test for the offline cold-launch race: screens opened while
/// DownloadManager.initialize() is still loading the saved queue read (and
/// cache) an empty queue, and on an offline launch no connect/disconnect
/// event ever corrects them. Initialization must broadcast the restored
/// scoped queue on [DownloadManager.queueStream] so early-built consumers
/// converge on the real download state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity');
  const connectivityStatusChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity_status');
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Directory docsDir;
  final secureStorage = <String, String>{};

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    docsDir =
        await Directory.systemTemp.createTemp('ariami_startup_broadcast_');

    // Keep this file's database out of the shared FFI default directory so it
    // cannot lock horns with download_manager_test.dart when the suite runs
    // test files concurrently.
    await databaseFactory.setDatabasesPath(p.join(docsDir.path, 'databases'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getExternalCacheDirectories':
        case 'getExternalStorageDirectories':
          return <String>[docsDir.path];
        default:
          return docsDir.path;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
      if (call.method == 'check') {
        return <String>['none'];
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityStatusChannel, (call) async {
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = (call.arguments as Map<dynamic, dynamic>? ?? const {});
      final key = args['key'] as String?;

      switch (call.method) {
        case 'read':
          if (key == null) return null;
          return secureStorage[key];
        case 'write':
          if (key != null) {
            secureStorage[key] = (args['value'] as String?) ?? '';
          }
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStorage);
        case 'containsKey':
          if (key == null) return false;
          return secureStorage.containsKey(key);
        default:
          return null;
      }
    });

    final dbRoot = await getDatabasesPath();
    await deleteDatabase(p.join(dbRoot, 'downloads.db'));

    SharedPreferences.setMockInitialValues(
      <String, Object>{
        'download_queue': <String>[
          jsonEncode(
            DownloadTask(
              id: 'song_song-complete',
              songId: 'song-complete',
              title: 'Complete',
              artist: 'Test Artist',
              albumId: 'album-1',
              albumName: 'Album album-1',
              albumArtist: 'Test Album Artist',
              albumArt: 'https://example.com/art.jpg',
              downloadUrl: 'https://example.com/download/song-complete',
              status: DownloadStatus.completed,
              bytesDownloaded: 1000,
              totalBytes: 1000,
            ).toJson(),
          ),
        ],
      },
    );

    final songsDir = Directory(p.join(docsDir.path, 'downloads', 'songs'));
    await songsDir.create(recursive: true);
    await File(p.join(songsDir.path, 'song-complete.mp3'))
        .writeAsBytes(List<int>.filled(32, 1));
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityStatusChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);

    if (await docsDir.exists()) {
      await docsDir.delete(recursive: true);
    }
  });

  test(
      'initialization broadcasts the restored queue to consumers that '
      'subscribed and read before initialize() completed', () async {
    final manager = DownloadManager();

    // A screen opened "too quickly" subscribes to queueStream and reads the
    // queue synchronously before initialization has loaded the saved tasks.
    // The read also latches the empty result into the scoped-queue cache,
    // which is what kept downloads looking absent after init completed.
    final emissions = <List<DownloadTask>>[];
    final firstEmission = Completer<List<DownloadTask>>();
    final subscription = manager.queueStream.listen((tasks) {
      emissions.add(tasks);
      if (!firstEmission.isCompleted) {
        firstEmission.complete(tasks);
      }
    });
    addTearDown(subscription.cancel);

    expect(manager.queue, isEmpty,
        reason: 'sanity: the early read happens before initialization');

    await manager.initialize();

    final broadcast = await firstEmission.future
        .timeout(const Duration(seconds: 5), onTimeout: () {
      fail('initialize() never broadcast the restored queue on queueStream');
    });

    expect(
      broadcast.map((task) => task.songId),
      contains('song-complete'),
      reason: 'the post-initialization broadcast must carry the saved tasks',
    );

    // The synchronous read path must also see the restored queue, i.e. the
    // stale empty scoped-queue cache from the early read was invalidated.
    expect(
      manager.queue.map((task) => task.songId),
      contains('song-complete'),
    );
  });
}
