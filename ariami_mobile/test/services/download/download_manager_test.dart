import 'dart:convert';
import 'dart:io';

import 'package:ariami_mobile/models/download_task.dart';
import 'package:ariami_mobile/services/download/download_helpers.dart';
import 'package:ariami_mobile/services/download/download_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  late DownloadManager manager;
  final secureStorage = <String, String>{};

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    docsDir = await Directory.systemTemp.createTemp('ariami_downloads_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getTemporaryDirectory':
        case 'getApplicationSupportDirectory':
        case 'getLibraryDirectory':
        case 'getExternalStorageDirectory':
          return docsDir.path;
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
        return <String>['wifi'];
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityStatusChannel, (call) async {
      if (call.method == 'listen' || call.method == 'cancel') {
        return null;
      }
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
        case 'delete':
          if (key != null) {
            secureStorage.remove(key);
          }
          return null;
        case 'deleteAll':
          secureStorage.clear();
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
    await deleteDatabase(p.join(dbRoot, 'library_sync.db'));
    await deleteDatabase(p.join(dbRoot, 'cache_metadata.db'));

    SharedPreferences.setMockInitialValues(
      <String, Object>{
        'download_queue': <String>[
          jsonEncode(
            _task(
              id: 'song_song-complete',
              songId: 'song-complete',
              title: 'Complete',
              status: DownloadStatus.completed,
              bytesDownloaded: 1000,
              totalBytes: 900,
              albumId: 'album-1',
            ).toJson(),
          ),
          jsonEncode(
            _task(
              id: 'song_song-pending',
              songId: 'song-pending',
              title: 'Pending',
              status: DownloadStatus.pending,
              totalBytes: 400,
              albumId: 'album-2',
            ).toJson(),
          ),
          jsonEncode(
            _task(
              id: 'song_song-downloading',
              songId: 'song-downloading',
              title: 'Downloading',
              status: DownloadStatus.downloading,
              bytesDownloaded: 120,
              totalBytes: 300,
              albumId: 'album-3',
            ).toJson(),
          ),
          jsonEncode(
            _task(
              id: 'song_song-manual-paused',
              songId: 'song-manual-paused',
              title: 'Manual Pause',
              status: DownloadStatus.paused,
              totalBytes: 500,
              albumId: 'album-4',
              errorMessage: 'User paused this download',
            ).toJson(),
          ),
        ],
      },
    );

    final songsDir = Directory(p.join(docsDir.path, 'downloads', 'songs'));
    await songsDir.create(recursive: true);
    await File(p.join(songsDir.path, 'song-complete.mp3'))
        .writeAsBytes(List<int>.filled(32, 1));
    await File(p.join(songsDir.path, 'stale-song.mp3'))
        .writeAsBytes(List<int>.filled(16, 2));

    manager = DownloadManager();
    await manager.initialize();
  });

  tearDownAll(() async {
    await manager.clearAllDownloads();
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

  group('DownloadManager refactor regression', () {
    test('initialization keeps queue semantics and derived stats', () async {
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final queue = manager.queue;
      expect(queue.length, 4);
      expect(
        queue.where((task) => task.status == DownloadStatus.completed).length,
        1,
      );
      expect(
        queue.where((task) => task.status == DownloadStatus.paused).length,
        3,
      );

      final pendingTask =
          queue.firstWhere((task) => task.songId == 'song-pending');
      final downloadingTask =
          queue.firstWhere((task) => task.songId == 'song-downloading');
      final manuallyPausedTask =
          queue.firstWhere((task) => task.songId == 'song-manual-paused');

      expect(pendingTask.errorMessage, appClosedDownloadPauseMessage);
      expect(downloadingTask.errorMessage, appClosedDownloadPauseMessage);
      expect(manuallyPausedTask.errorMessage, 'User paused this download');

      final stats = manager.getQueueStats();
      expect(stats.totalTasks, 4);
      expect(stats.completed, 1);
      expect(stats.downloading, 0);
      expect(stats.failed, 0);
      expect(stats.paused, 3);
      expect(stats.totalBytes, 2100);
      expect(stats.downloadedBytes, 1120);

      expect(await manager.isSongDownloaded('song-complete'), isTrue);
      expect(manager.getCompletedDownloadCount(), 1);
      expect(manager.getInterruptedDownloadCount(), 2);
      expect(
        manager.getDownloadedSongPath('song-complete'),
        endsWith('/downloads/songs/song-complete.mp3'),
      );
      expect(
        manager.getAnyDownloadedSongPathForAlbum('album-1'),
        endsWith('/downloads/songs/song-complete.mp3'),
      );
      expect(
        manager.getTotalDownloadedSizeMB(),
        closeTo(1000 / (1024 * 1024), 0.0000001),
      );

      expect(
        File(p.join(docsDir.path, 'downloads', 'songs', 'song-complete.mp3'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(docsDir.path, 'downloads', 'songs', 'stale-song.mp3'))
            .existsSync(),
        isFalse,
      );
    });

    test('resume, prune, and clear operations preserve behavior', () async {
      final resumedCount = await manager.resumeInterruptedDownloads();
      expect(resumedCount, 2);
      expect(manager.getInterruptedDownloadCount(), 0);

      final queueAfterResume = manager.queue;
      final resumedTasks = queueAfterResume
          .where((task) =>
              task.songId == 'song-pending' ||
              task.songId == 'song-downloading')
          .toList(growable: false);
      expect(
        resumedTasks.every((task) => task.status == DownloadStatus.pending),
        isTrue,
      );
      expect(resumedTasks.every((task) => task.errorMessage == null), isTrue);

      final cancelledInterrupted = await manager.cancelInterruptedDownloads();
      expect(cancelledInterrupted, 0);

      final prunedCount = await manager.pruneOrphanedDownloads(
        <String>{'song-complete', 'song-manual-paused'},
      );
      expect(prunedCount, 2);
      await Future<void>.delayed(Duration.zero);
      expect(
        manager.queue.map((task) => task.songId).toSet(),
        <String>{'song-complete', 'song-manual-paused'},
      );

      final songsDir = Directory(p.join(docsDir.path, 'downloads', 'songs'));
      await songsDir.create(recursive: true);
      await File(p.join(songsDir.path, 'song-manual-paused.mp3'))
          .writeAsBytes(List<int>.filled(64, 3));
      await File(p.join(songsDir.path, 'stray-before-clear.mp3'))
          .writeAsBytes(List<int>.filled(64, 4));

      await manager.clearAllDownloads();
      await Future<void>.delayed(Duration.zero);
      expect(manager.queue, isEmpty);
      expect(manager.getQueueStats().totalTasks, 0);
      expect(manager.getCompletedDownloadCount(), 0);
      expect(
        File(p.join(docsDir.path, 'downloads', 'songs', 'song-complete.mp3'))
            .existsSync(),
        isFalse,
      );
      expect(
        File(p.join(
                docsDir.path, 'downloads', 'songs', 'song-manual-paused.mp3'))
            .existsSync(),
        isFalse,
      );
      expect(
        File(p.join(
                docsDir.path, 'downloads', 'songs', 'stray-before-clear.mp3'))
            .existsSync(),
        isFalse,
      );
    });
  });
}

DownloadTask _task({
  required String id,
  required String songId,
  required String title,
  required DownloadStatus status,
  int bytesDownloaded = 0,
  required int totalBytes,
  String? albumId,
  String? errorMessage,
}) {
  return DownloadTask(
    id: id,
    songId: songId,
    title: title,
    artist: 'Test Artist',
    albumId: albumId,
    albumName: albumId == null ? null : 'Album $albumId',
    albumArtist: 'Test Album Artist',
    albumArt: 'https://example.com/art.jpg',
    downloadUrl: 'https://example.com/download/$songId',
    status: status,
    bytesDownloaded: bytesDownloaded,
    totalBytes: totalBytes,
    errorMessage: errorMessage,
  );
}
