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
  });
}

Future<void> _writeAudioStub(String filePath) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(List<int>.filled(1024, 0), flush: true);
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
