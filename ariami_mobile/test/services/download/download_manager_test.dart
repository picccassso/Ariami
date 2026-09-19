import 'dart:convert';
import 'dart:io';

import 'package:ariami_mobile/database/download_database.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/download_task.dart';
import 'package:ariami_mobile/services/cache/cache_manager.dart';
import 'package:ariami_mobile/services/download/download_helpers.dart';
import 'package:ariami_mobile/services/download/download_manager.dart';
import 'package:dio/dio.dart';
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

    // Keep this file's databases out of the shared FFI default directory so
    // concurrent test files can't lock or delete each other's databases.
    await databaseFactory.setDatabasesPath(p.join(docsDir.path, 'databases'));

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
    await File(p.join(songsDir.path, 'song-pending.mp3.partial'))
        .writeAsBytes(List<int>.filled(24, 7));
    await File(p.join(songsDir.path, 'stale-song.mp3'))
        .writeAsBytes(List<int>.filled(16, 2));
    await File(p.join(songsDir.path, 'stale-song.mp3.partial'))
        .writeAsBytes(List<int>.filled(16, 3));

    manager = DownloadManager();
    await manager.initialize();
  });

  tearDownAll(() async {
    // Both singletons kick off fire-and-forget work during initialization
    // that keeps reading and writing inside docsDir. Deleting the directory
    // while those passes are still running fails the teardown outright
    // ("Directory not empty") and takes any database still open in there
    // down with it, so let them finish before the directory goes.
    await DownloadManager().settleBackgroundWork();
    await CacheManager().settleBackgroundWork();

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
      expect(pendingTask.bytesDownloaded, 24);

      final stats = manager.getQueueStats();
      expect(stats.totalTasks, 4);
      expect(stats.completed, 1);
      expect(stats.downloading, 0);
      expect(stats.failed, 0);
      expect(stats.paused, 3);
      expect(stats.totalBytes, 2100);
      expect(stats.downloadedBytes, 1144);

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
        isTrue,
      );
      expect(
        File(p.join(
                docsDir.path, 'downloads', 'songs', 'song-pending.mp3.partial'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(
                docsDir.path, 'downloads', 'songs', 'stale-song.mp3.partial'))
            .existsSync(),
        isTrue,
      );
    });

    test('a final file restores a stale unfinished task to completed',
        () async {
      final songsDir = Directory(p.join(docsDir.path, 'downloads', 'songs'));
      final finalFile = File(p.join(songsDir.path, 'recovered-song.opus'));
      await finalFile.writeAsBytes(List<int>.filled(96, 4));
      final task = _task(
        id: 'song_recovered-song',
        songId: 'recovered-song',
        title: 'Recovered Song',
        status: DownloadStatus.downloading,
        bytesDownloaded: 48,
        totalBytes: 96,
        downloadFileExtension: 'opus',
      );

      final recovered = await manager.recoverCompletedFinalFile(task);

      expect(recovered, isTrue);
      expect(task.status, DownloadStatus.completed);
      expect(task.progress, 1);
      expect(task.bytesDownloaded, 96);
      expect(task.totalBytes, 96);
      expect(finalFile.existsSync(), isTrue);
    });

    test('completed status is durable before the transfer is reported done',
        () async {
      final task = _task(
        id: 'song_durable-complete',
        songId: 'durable-complete',
        title: 'Durable Complete',
        status: DownloadStatus.pending,
        totalBytes: 128,
        downloadFileExtension: 'opus',
      );
      manager.enqueueTasksForTesting(<DownloadTask>[task]);
      task.status = DownloadStatus.completed;
      task.progress = 1;
      task.bytesDownloaded = 128;

      await manager.persistCompletedTaskDurablyForTest(task);

      final database = await DownloadDatabase.create();
      final persisted = (await database.loadDownloadQueue())
          .singleWhere((row) => row.id == task.id);
      expect(persisted.status, DownloadStatus.completed);
      expect(persisted.bytesDownloaded, 128);
      manager.cancelDownload(task.id);
    });

    test('partial library snapshots cannot prune unfinished downloads',
        () async {
      final beforeIds = manager.queue.map((task) => task.id).toSet();
      final partialPath = p.join(
        docsDir.path,
        'downloads',
        'songs',
        'song-pending.mp3.partial',
      );

      final removed = await manager.pruneOrphanedIncompleteDownloads(
        const <String>{'song-complete'},
        isAuthoritativeLibrary: false,
      );

      expect(removed, 0);
      expect(manager.queue.map((task) => task.id).toSet(), beforeIds);
      expect(File(partialPath).existsSync(), isTrue);
    });

    test('relinks a completed download only for one metadata match', () async {
      final album = AlbumModel(
        id: 'album-1',
        title: 'Album album-1',
        artist: 'Test Album Artist',
        songCount: 1,
        duration: 0,
      );
      SongModel song(String id) => SongModel(
            id: id,
            title: 'Complete',
            artist: 'Test Artist',
            albumId: album.id,
            duration: 0,
          );

      await manager.refreshDownloadAlbumMetadata(
        libraryAlbums: [
          AlbumModel(
            id: album.id,
            title: album.title,
            artist: 'Various Artists',
            songCount: album.songCount,
            duration: album.duration,
          ),
        ],
      );

      final relinked = await manager.relinkOrphanedCompletedDownloads(
        librarySongs: [song('song-restored')],
        libraryAlbums: [album],
      );

      expect(relinked, 1);
      expect(await manager.isSongDownloaded('song-restored'), isTrue);
      expect(await manager.isSongDownloaded('song-complete'), isFalse);
      expect(
        File(p.join(docsDir.path, 'downloads', 'songs', 'song-restored.mp3'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(docsDir.path, 'downloads', 'songs', 'song-complete.mp3'))
            .existsSync(),
        isFalse,
      );

      final relinkedBack = await manager.relinkOrphanedCompletedDownloads(
        librarySongs: [song('song-complete')],
        libraryAlbums: [album],
      );
      expect(relinkedBack, 1);

      final ambiguous = await manager.relinkOrphanedCompletedDownloads(
        librarySongs: [song('candidate-a'), song('candidate-b')],
        libraryAlbums: [album],
      );
      expect(ambiguous, 0);
      expect(await manager.isSongDownloaded('song-complete'), isTrue);
    });

    test('refreshes saved album metadata from an authoritative snapshot',
        () async {
      final refreshed = await manager.refreshDownloadAlbumMetadata(
        libraryAlbums: [
          AlbumModel(
            id: 'album-1',
            title: 'Correct Album',
            artist: 'Correct Album Artist',
            coverArt: 'https://example.com/correct-art.jpg',
            songCount: 1,
            duration: 0,
          ),
        ],
      );

      final task =
          manager.queue.firstWhere((task) => task.songId == 'song-complete');
      expect(refreshed, 1);
      expect(task.albumName, 'Correct Album');
      expect(task.albumArtist, 'Correct Album Artist');
      expect(task.albumArt, 'https://example.com/correct-art.jpg');
    });

    test('migrates album IDs when album identity changes but song is unchanged',
        () async {
      // Precondition: the completed download is linked to 'album-1'.
      final before =
          manager.queue.firstWhere((task) => task.songId == 'song-complete');
      expect(before.albumId, 'album-1');

      // The server re-hashed the album ID (e.g. tag normalization) but the
      // song itself (path-derived id) is unchanged.
      const newAlbumId = 'album-1-clean';
      final migrated = await manager.migrateDownloadAlbumIds(
        librarySongs: [
          SongModel(
            id: 'song-complete',
            title: 'Complete',
            artist: 'Test Artist',
            albumId: newAlbumId,
            duration: 0,
          ),
        ],
        libraryAlbums: [
          AlbumModel(
            id: newAlbumId,
            title: 'These Things Happen',
            artist: 'G-Eazy',
            coverArt: 'https://example.com/clean-art.jpg',
            songCount: 1,
            duration: 0,
          ),
        ],
      );

      expect(migrated, {'album-1': newAlbumId});
      final after =
          manager.queue.firstWhere((task) => task.songId == 'song-complete');
      expect(after.albumId, newAlbumId);
      expect(after.albumName, 'These Things Happen');
      expect(after.albumArtist, 'G-Eazy');
      // The download itself is untouched - still present under its stable songId.
      expect(await manager.isSongDownloaded('song-complete'), isTrue);

      // A second pass with the now-current album ID is a no-op.
      final again = await manager.migrateDownloadAlbumIds(
        librarySongs: [
          SongModel(
            id: 'song-complete',
            title: 'Complete',
            artist: 'Test Artist',
            albumId: newAlbumId,
            duration: 0,
          ),
        ],
        libraryAlbums: [
          AlbumModel(
            id: newAlbumId,
            title: 'These Things Happen',
            artist: 'G-Eazy',
            songCount: 1,
            duration: 0,
          ),
        ],
      );
      expect(again, isEmpty);
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

    test(
        'stale cleanup preserves non-mp3 formats (.opus, .m4a, .flac) and '
        'only removes redundant partials with a durable completed file',
        () async {
      final songsDir = Directory(p.join(docsDir.path, 'downloads', 'songs'));
      await songsDir.create(recursive: true);

      // Create test tasks with various formats:
      // 1. song-opus-ok: completed opus download
      // 2. song-m4a-ok: completed m4a download
      // 3. song-flac-ok: completed flac download (album-flac)
      // 4. song-opus-in-progress: downloading opus partial
      final testTasks = [
        _task(
          id: 'song_song-opus-ok',
          songId: 'song-opus-ok',
          title: 'Opus Song',
          status: DownloadStatus.completed,
          bytesDownloaded: 500,
          totalBytes: 500,
          downloadFileExtension: 'opus',
        ),
        _task(
          id: 'song_song-m4a-ok',
          songId: 'song-m4a-ok',
          title: 'M4A Song',
          status: DownloadStatus.completed,
          bytesDownloaded: 600,
          totalBytes: 600,
          downloadFileExtension: 'm4a',
        ),
        _task(
          id: 'song_song-flac-ok',
          songId: 'song-flac-ok',
          title: 'FLAC Song',
          status: DownloadStatus.completed,
          bytesDownloaded: 1200,
          totalBytes: 1200,
          albumId: 'album-flac',
          downloadFileExtension: 'flac',
        ),
        _task(
          id: 'song_song-opus-in-progress',
          songId: 'song-opus-in-progress',
          title: 'Opus Downloading',
          status: DownloadStatus.downloading,
          bytesDownloaded: 200,
          totalBytes: 800,
          downloadFileExtension: 'opus',
        ),
      ];
      manager.enqueueTasksForTesting(testTasks);

      // Populate files on disk:
      // Valid files to keep:
      final opusFile = File(p.join(songsDir.path, 'song-opus-ok.opus'));
      await opusFile.writeAsBytes(List<int>.filled(64, 1));

      final m4aFile = File(p.join(songsDir.path, 'song-m4a-ok.m4a'));
      await m4aFile.writeAsBytes(List<int>.filled(64, 2));

      final flacFile = File(p.join(songsDir.path, 'song-flac-ok.flac'));
      await flacFile.writeAsBytes(List<int>.filled(64, 3));

      final partialFile =
          File(p.join(songsDir.path, 'song-opus-in-progress.opus.partial'));
      await partialFile.writeAsBytes(List<int>.filled(64, 4));

      // Stale files to prune:
      // 1. Old leftover format for an already migrated completed song
      final staleOldFormat = File(p.join(songsDir.path, 'song-opus-ok.mp3'));
      await staleOldFormat.writeAsBytes(List<int>.filled(64, 5));

      // 2. Leftover partial for an already completed song
      final staleCompletedPartial =
          File(p.join(songsDir.path, 'song-opus-ok.opus.partial'));
      await staleCompletedPartial.writeAsBytes(List<int>.filled(64, 6));

      // 3. Unreferenced non-mp3 files
      final staleUnreferencedOpus =
          File(p.join(songsDir.path, 'ghost-song.opus'));
      await staleUnreferencedOpus.writeAsBytes(List<int>.filled(64, 7));

      final staleUnreferencedFlac =
          File(p.join(songsDir.path, 'ghost-song.flac'));
      await staleUnreferencedFlac.writeAsBytes(List<int>.filled(64, 8));

      final staleUnreferencedPartial =
          File(p.join(songsDir.path, 'ghost-song.m4a.partial'));
      await staleUnreferencedPartial.writeAsBytes(List<int>.filled(64, 9));

      // 4. Hidden non-audio file
      final dsStore = File(p.join(songsDir.path, '.DS_Store'));
      await dsStore.writeAsBytes(List<int>.filled(16, 0));

      final removedCount = await manager.cleanupStaleDownloadFiles();
      expect(removedCount, 1);

      // Verify legitimate files were preserved
      expect(opusFile.existsSync(), isTrue);
      expect(m4aFile.existsSync(), isTrue);
      expect(flacFile.existsSync(), isTrue);
      expect(partialFile.existsSync(), isTrue);

      // The completed task proves only its matching partial is redundant.
      // Unknown/mismatched final files are preserved because a lost database
      // write must never erase a successfully downloaded library.
      expect(staleOldFormat.existsSync(), isTrue);
      expect(staleCompletedPartial.existsSync(), isFalse);
      expect(staleUnreferencedOpus.existsSync(), isTrue);
      expect(staleUnreferencedFlac.existsSync(), isTrue);
      expect(staleUnreferencedPartial.existsSync(), isTrue);
      expect(dsStore.existsSync(), isTrue);

      // Verify path resolution respects task extension
      expect(
        manager.getDownloadedSongPath('song-opus-ok'),
        endsWith('/downloads/songs/song-opus-ok.opus'),
      );
      expect(
        manager.getDownloadedSongPath('song-m4a-ok'),
        endsWith('/downloads/songs/song-m4a-ok.m4a'),
      );
      expect(
        manager.getAnyDownloadedSongPathForAlbum('album-flac'),
        endsWith('/downloads/songs/song-flac-ok.flac'),
      );

      // Verify deletion of non-mp3 downloads
      await manager.deleteSongDownloads(['song-opus-ok']);
      expect(opusFile.existsSync(), isFalse);

      await manager.deleteAlbumDownloads('album-flac');
      expect(flacFile.existsSync(), isFalse);
    });

    test('transcoded downloads cache full server artwork for offline use',
        () async {
      final songsDir = Directory(p.join(docsDir.path, 'downloads', 'songs'));
      await songsDir.create(recursive: true);
      final opusFile = File(p.join(songsDir.path, 'song-art-repair.opus'));
      await opusFile.writeAsBytes(List<int>.filled(64, 0));

      final artworkBytes = List<int>.generate(4096, (index) => index % 251);
      final artworkAdapter = _DownloadArtworkAdapter(artworkBytes);
      CacheManager().setHttpClientAdapterForTests(artworkAdapter);

      try {
        final task = DownloadTask(
          id: 'song_song-art-repair',
          songId: 'song-art-repair',
          title: 'Artwork Repair',
          artist: 'Test Artist',
          albumId: 'album-art-repair',
          albumName: 'Artwork Repair Album',
          albumArtist: 'Test Album Artist',
          albumArt: 'https://ariami.test/cover.jpg?size=thumbnail',
          downloadUrl: 'https://example.com/download/song-art-repair',
          downloadOriginal: false,
          downloadFileExtension: 'opus',
          status: DownloadStatus.completed,
          totalBytes: 64,
        );

        expect(await manager.cacheDownloadedArtwork(task), isTrue);

        final cachedPath =
            await CacheManager().getArtworkPath('album-art-repair');
        expect(cachedPath, isNotNull);
        expect(await File(cachedPath!).readAsBytes(), artworkBytes);
        expect(artworkAdapter.requestedUri?.path, '/cover.jpg');
        expect(
          artworkAdapter.requestedUri?.queryParameters.containsKey('size'),
          isFalse,
        );
      } finally {
        await opusFile.delete();
      }
    });
  });
}

class _DownloadArtworkAdapter implements HttpClientAdapter {
  _DownloadArtworkAdapter(this.bytes);

  final List<int> bytes;
  Uri? requestedUri;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUri = options.uri;
    return ResponseBody.fromBytes(
      bytes,
      HttpStatus.ok,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['image/jpeg'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
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
  String? downloadFileExtension,
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
    downloadFileExtension: downloadFileExtension,
    status: status,
    bytesDownloaded: bytesDownloaded,
    totalBytes: totalBytes,
    errorMessage: errorMessage,
  );
}
