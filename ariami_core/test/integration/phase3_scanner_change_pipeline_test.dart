import 'dart:async';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:ariami_core/services/catalog/catalog_database.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Phase 3 - scanner and change pipeline', () {
    late Directory testDir;
    late Directory musicDir;
    late LibraryManager libraryManager;

    setUp(() async {
      testDir = await Directory.systemTemp.createTemp('ariami_phase3_');
      musicDir = await Directory(p.join(testDir.path, 'music')).create();

      libraryManager = LibraryManager();
      libraryManager.clear();
      libraryManager.setCachePath(p.join(testDir.path, 'metadata_cache.json'));
    });

    tearDown(() async {
      libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test(
      'P3-1: full scan writes catalog rows matching in-memory counts and advances latestToken',
      () async {
        await _writeAudioStub(
            p.join(musicDir.path, 'Artist One - Track 01.mp3'));
        await _writeAudioStub(
            p.join(musicDir.path, 'Artist One - Track 02.mp3'));
        await _writeAudioStub(
            p.join(musicDir.path, 'Artist Two - Track 03.mp3'));

        final startingToken = libraryManager.latestToken;

        await libraryManager.scanMusicFolder(musicDir.path);

        final library = libraryManager.library;
        expect(library, isNotNull);

        final db =
            CatalogDatabase(databasePath: p.join(testDir.path, 'catalog.db'));
        db.initialize();
        final repository = CatalogRepository(database: db.database);
        addTearDown(db.close);

        final catalogSongCount = _countSongs(repository);
        final catalogAlbumCount = _countAlbums(repository);

        expect(catalogSongCount, equals(library!.totalSongs));
        expect(catalogAlbumCount, equals(library.totalAlbums));
        expect(libraryManager.latestToken, greaterThan(startingToken));
        expect(repository.getLatestToken(), equals(libraryManager.latestToken));
      },
    );

    test(
      'P3-2: add/remove/rename file batches create monotonic library_changes tokens',
      () async {
        final originalPath =
            p.join(musicDir.path, 'Source Artist - Source Song.mp3');
        final incomingPath = p.join(testDir.path, 'incoming_song.mp3');
        final addedPath =
            p.join(musicDir.path, 'Added Artist - Added Song.mp3');
        final renamedPath =
            p.join(musicDir.path, 'Renamed Artist - Renamed Song.mp3');

        await _writeAudioStub(originalPath);
        await _writeAudioStub(incomingPath);
        await libraryManager.scanMusicFolder(musicDir.path);

        final tokenAfterScan = libraryManager.latestToken;
        expect(tokenAfterScan, greaterThan(0));

        // Give DirectoryWatcher time to stabilize after initial startWatching call.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        await File(incomingPath).rename(addedPath);
        final tokenAfterAdd = await _waitForTokenAdvance(
          libraryManager: libraryManager,
          previousToken: tokenAfterScan,
          timeout: const Duration(seconds: 30),
        );

        await File(addedPath).rename(renamedPath);
        final tokenAfterRename = await _waitForTokenAdvance(
          libraryManager: libraryManager,
          previousToken: tokenAfterAdd,
          timeout: const Duration(seconds: 30),
        );

        await File(renamedPath).delete();
        final tokenAfterDelete = await _waitForTokenAdvance(
          libraryManager: libraryManager,
          previousToken: tokenAfterRename,
          timeout: const Duration(seconds: 30),
        );

        final db =
            CatalogDatabase(databasePath: p.join(testDir.path, 'catalog.db'));
        db.initialize();
        final repository = CatalogRepository(database: db.database);
        addTearDown(db.close);

        final addEvents = repository
            .readChangesSince(tokenAfterScan, 2000)
            .where((event) => event.token <= tokenAfterAdd)
            .toList();
        final renameEvents = repository
            .readChangesSince(tokenAfterAdd, 2000)
            .where((event) => event.token <= tokenAfterRename)
            .toList();
        final deleteEvents = repository
            .readChangesSince(tokenAfterRename, 2000)
            .where((event) => event.token <= tokenAfterDelete)
            .toList();

        expect(
          addEvents.any(
              (event) => event.entityType == 'song' && event.op == 'upsert'),
          isTrue,
        );
        expect(
          addEvents.where((event) => event.op == 'upsert').every((event) =>
              event.payloadJson != null && event.payloadJson!.isNotEmpty),
          isTrue,
        );
        expect(
          renameEvents.any(
              (event) => event.entityType == 'song' && event.op == 'upsert'),
          isTrue,
        );
        expect(
          renameEvents.where((event) => event.op == 'upsert').every((event) =>
              event.payloadJson != null && event.payloadJson!.isNotEmpty),
          isTrue,
        );
        expect(
          renameEvents.any(
              (event) => event.entityType == 'song' && event.op == 'delete'),
          isTrue,
        );
        expect(
          deleteEvents.any(
              (event) => event.entityType == 'song' && event.op == 'delete'),
          isTrue,
        );

        final allEvents = repository.readChangesSince(tokenAfterScan, 5000);
        for (var i = 1; i < allEvents.length; i++) {
          expect(allEvents[i].token, greaterThan(allEvents[i - 1].token));
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'P3-3: full rescan refreshes cached metadata entries that are missing duration',
      () async {
        final cachedSongPath = p.join(musicDir.path, 'cached song.mp3');
        await _copyFixtureAudio(
          sourceFileName: 'Atat De Liberi.mp3',
          destinationPath: cachedSongPath,
        );

        final stat = await File(cachedSongPath).stat();
        final staleCache = MetadataCache(
          p.join(testDir.path, 'metadata_cache.json'),
        );
        staleCache.putWithStats(
          cachedSongPath,
          SongMetadata(
            filePath: cachedSongPath,
            title: 'cached song',
            fileSize: stat.size,
            modifiedTime: stat.modified,
          ),
          stat.modified.millisecondsSinceEpoch,
          stat.size,
        );
        await staleCache.save();

        await libraryManager.scanMusicFolder(musicDir.path);

        final scannedSong = _findSongByPath(
          libraryManager.library!,
          cachedSongPath,
        );
        expect(scannedSong, isNotNull);
        expect(scannedSong!.duration, greaterThan(0));

        final refreshedCache = MetadataCache(
          p.join(testDir.path, 'metadata_cache.json'),
        );
        await refreshedCache.load();
        final cachedMetadata = await refreshedCache.get(cachedSongPath);
        expect(cachedMetadata, isNotNull);
        expect(cachedMetadata!.duration, greaterThan(0));
      },
    );

    test(
      'P3-4: incremental file adds persist duration during change processing',
      () async {
        final originalPath = p.join(musicDir.path, 'initial song.mp3');
        await _copyFixtureAudio(
          sourceFileName: 'A Very Strange Time.mp3',
          destinationPath: originalPath,
        );
        await libraryManager.scanMusicFolder(musicDir.path);

        final tokenAfterScan = libraryManager.latestToken;

        await Future<void>.delayed(const Duration(milliseconds: 500));

        final addedPath = p.join(musicDir.path, 'added song.mp3');
        await _copyFixtureAudio(
          sourceFileName: 'Everything is Everything.mp3',
          destinationPath: addedPath,
        );

        await _waitForTokenAdvance(
          libraryManager: libraryManager,
          previousToken: tokenAfterScan,
          timeout: const Duration(seconds: 30),
        );

        final addedSong = await _waitForSongByPath(
          libraryManager: libraryManager,
          filePath: addedPath,
        );
        expect(addedSong.duration, greaterThan(0));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}

Future<void> _writeAudioStub(String filePath) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(List<int>.filled(1024, 0), flush: true);
}

Future<void> _copyFixtureAudio({
  required String sourceFileName,
  required String destinationPath,
}) async {
  final sourcePath = p.normalize(
      p.join(Directory.current.path, '..', 'examples', sourceFileName));
  final destinationFile = File(destinationPath);
  await destinationFile.parent.create(recursive: true);
  await File(sourcePath).copy(destinationPath);
}

int _countSongs(CatalogRepository repository) {
  var count = 0;
  String? cursor;
  do {
    final page = repository.listSongsPage(cursor: cursor, limit: 100);
    count += page.items.length;
    cursor = page.nextCursor;
    if (!page.hasMore) {
      break;
    }
  } while (true);
  return count;
}

int _countAlbums(CatalogRepository repository) {
  var count = 0;
  String? cursor;
  do {
    final page = repository.listAlbumsPage(cursor: cursor, limit: 100);
    count += page.items.length;
    cursor = page.nextCursor;
    if (!page.hasMore) {
      break;
    }
  } while (true);
  return count;
}

SongMetadata? _findSongByPath(LibraryStructure library, String filePath) {
  for (final album in library.albums.values) {
    for (final song in album.songs) {
      if (song.filePath == filePath) {
        return song;
      }
    }
  }

  for (final song in library.standaloneSongs) {
    if (song.filePath == filePath) {
      return song;
    }
  }

  return null;
}

Future<SongMetadata> _waitForSongByPath({
  required LibraryManager libraryManager,
  required String filePath,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    final library = libraryManager.library;
    if (library != null) {
      final song = _findSongByPath(library, filePath);
      if (song != null) {
        return song;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  fail('Timed out waiting for song to appear: $filePath');
}

Future<int> _waitForTokenAdvance({
  required LibraryManager libraryManager,
  required int previousToken,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    final currentToken = libraryManager.latestToken;
    if (currentToken > previousToken) {
      return currentToken;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  fail(
    'Timed out waiting for latestToken to advance beyond '
    '$previousToken (current: ${libraryManager.latestToken}).',
  );
}
