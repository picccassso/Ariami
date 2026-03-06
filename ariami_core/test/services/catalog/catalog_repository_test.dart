import 'dart:io';

import 'package:ariami_core/services/catalog/catalog_database.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:test/test.dart';

void main() {
  late Directory rootTempDir;

  setUpAll(() async {
    rootTempDir =
        await Directory.systemTemp.createTemp('ariami_catalog_repository_');
  });

  tearDownAll(() async {
    if (await rootTempDir.exists()) {
      await rootTempDir.delete(recursive: true);
    }
  });

  group('CatalogRepository pagination', () {
    late Directory testDir;
    late CatalogDatabase catalogDatabase;
    late CatalogRepository repository;

    setUp(() async {
      testDir = await rootTempDir.createTemp('pagination_');
      catalogDatabase =
          CatalogDatabase(databasePath: '${testDir.path}/catalog.db');
      catalogDatabase.initialize();
      repository = CatalogRepository(database: catalogDatabase.database);
    });

    tearDown(() async {
      catalogDatabase.close();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('listAlbumsPage returns stable ordering and cursor continuity', () {
      repository.upsertAlbum(
        CatalogAlbumRecord(
          id: 'album-c',
          title: 'Album C',
          artist: 'Artist',
          year: 2020,
          coverArtKey: null,
          songCount: 1,
          durationSeconds: 180,
          updatedToken: 1,
        ),
      );
      repository.upsertAlbum(
        CatalogAlbumRecord(
          id: 'album-a',
          title: 'Album A',
          artist: 'Artist',
          year: 2020,
          coverArtKey: null,
          songCount: 1,
          durationSeconds: 200,
          updatedToken: 1,
        ),
      );
      repository.upsertAlbum(
        CatalogAlbumRecord(
          id: 'album-b',
          title: 'Album B',
          artist: 'Artist',
          year: 2020,
          coverArtKey: null,
          songCount: 1,
          durationSeconds: 220,
          updatedToken: 1,
        ),
      );

      final CatalogPage<CatalogAlbumRecord> firstPage =
          repository.listAlbumsPage(limit: 2);
      expect(firstPage.items.map((item) => item.id).toList(),
          equals(<String>['album-a', 'album-b']));
      expect(firstPage.hasMore, isTrue);
      expect(firstPage.nextCursor, equals('album-b'));

      final CatalogPage<CatalogAlbumRecord> secondPage = repository
          .listAlbumsPage(cursor: firstPage.nextCursor, limit: firstPage.limit);
      expect(secondPage.items.map((item) => item.id).toList(),
          equals(<String>['album-c']));
      expect(secondPage.hasMore, isFalse);
      expect(secondPage.nextCursor, isNull);
    });

    test('listSongsPage paginates in ascending id order', () {
      repository.upsertSong(
        CatalogSongRecord(
          id: 'song-2',
          filePath: '/tmp/song-2.mp3',
          title: 'Song 2',
          artist: 'Artist',
          albumId: null,
          durationSeconds: 200,
          updatedToken: 1,
        ),
      );
      repository.upsertSong(
        CatalogSongRecord(
          id: 'song-1',
          filePath: '/tmp/song-1.mp3',
          title: 'Song 1',
          artist: 'Artist',
          albumId: null,
          durationSeconds: 190,
          updatedToken: 1,
        ),
      );
      repository.upsertSong(
        CatalogSongRecord(
          id: 'song-3',
          filePath: '/tmp/song-3.mp3',
          title: 'Song 3',
          artist: 'Artist',
          albumId: null,
          durationSeconds: 210,
          updatedToken: 1,
        ),
      );

      final CatalogPage<CatalogSongRecord> firstPage =
          repository.listSongsPage(limit: 2);
      expect(firstPage.items.map((item) => item.id).toList(),
          equals(<String>['song-1', 'song-2']));
      expect(firstPage.hasMore, isTrue);
      expect(firstPage.nextCursor, equals('song-2'));

      final CatalogPage<CatalogSongRecord> secondPage = repository
          .listSongsPage(cursor: firstPage.nextCursor, limit: firstPage.limit);
      expect(secondPage.items.map((item) => item.id).toList(),
          equals(<String>['song-3']));
      expect(secondPage.hasMore, isFalse);
      expect(secondPage.nextCursor, isNull);
    });

    test('listPlaylistsPage paginates in ascending id order', () {
      catalogDatabase.database.execute(
        '''
INSERT INTO playlists (id, name, song_count, updated_token, is_deleted)
VALUES
  ('playlist-2', 'Playlist 2', 2, 1, 0),
  ('playlist-1', 'Playlist 1', 1, 1, 0),
  ('playlist-3', 'Playlist 3', 3, 1, 0);
''',
      );

      final CatalogPage<CatalogPlaylistRecord> firstPage =
          repository.listPlaylistsPage(limit: 2);
      expect(firstPage.items.map((item) => item.id).toList(),
          equals(<String>['playlist-1', 'playlist-2']));
      expect(firstPage.hasMore, isTrue);
      expect(firstPage.nextCursor, equals('playlist-2'));

      final CatalogPage<CatalogPlaylistRecord> secondPage = repository
          .listPlaylistsPage(cursor: firstPage.nextCursor, limit: firstPage.limit);
      expect(secondPage.items.map((item) => item.id).toList(),
          equals(<String>['playlist-3']));
      expect(secondPage.hasMore, isFalse);
      expect(secondPage.nextCursor, isNull);
    });
  });

  group('CatalogRepository soft deletes', () {
    late Directory testDir;
    late CatalogDatabase catalogDatabase;
    late CatalogRepository repository;

    setUp(() async {
      testDir = await rootTempDir.createTemp('soft_delete_');
      catalogDatabase =
          CatalogDatabase(databasePath: '${testDir.path}/catalog.db');
      catalogDatabase.initialize();
      repository = CatalogRepository(database: catalogDatabase.database);
    });

    tearDown(() async {
      catalogDatabase.close();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('softDeleteAlbum and softDeleteSong mark deleted and hide from pages', () {
      repository.upsertAlbum(
        CatalogAlbumRecord(
          id: 'album-1',
          title: 'Album 1',
          artist: 'Artist',
          year: 2024,
          coverArtKey: null,
          songCount: 1,
          durationSeconds: 250,
          updatedToken: 10,
        ),
      );
      repository.upsertAlbum(
        CatalogAlbumRecord(
          id: 'album-2',
          title: 'Album 2',
          artist: 'Artist',
          year: 2024,
          coverArtKey: null,
          songCount: 1,
          durationSeconds: 260,
          updatedToken: 10,
        ),
      );
      repository.upsertSong(
        CatalogSongRecord(
          id: 'song-1',
          filePath: '/tmp/song-soft-1.mp3',
          title: 'Song 1',
          artist: 'Artist',
          albumId: 'album-1',
          durationSeconds: 250,
          updatedToken: 10,
        ),
      );
      repository.upsertSong(
        CatalogSongRecord(
          id: 'song-2',
          filePath: '/tmp/song-soft-2.mp3',
          title: 'Song 2',
          artist: 'Artist',
          albumId: 'album-2',
          durationSeconds: 260,
          updatedToken: 10,
        ),
      );

      repository.softDeleteAlbum('album-1', 21);
      repository.softDeleteSong('song-1', 22);

      final CatalogPage<CatalogAlbumRecord> albumsPage =
          repository.listAlbumsPage(limit: 10);
      expect(
        albumsPage.items.map((item) => item.id).toList(),
        equals(<String>['album-2']),
      );

      final CatalogPage<CatalogSongRecord> songsPage =
          repository.listSongsPage(limit: 10);
      expect(
        songsPage.items.map((item) => item.id).toList(),
        equals(<String>['song-2']),
      );

      final albumRow = catalogDatabase.database.select(
        'SELECT is_deleted, updated_token FROM albums WHERE id = ?;',
        <Object?>['album-1'],
      );
      expect(albumRow.first['is_deleted'], equals(1));
      expect(albumRow.first['updated_token'], equals(21));

      final songRow = catalogDatabase.database.select(
        'SELECT is_deleted, updated_token FROM songs WHERE id = ?;',
        <Object?>['song-1'],
      );
      expect(songRow.first['is_deleted'], equals(1));
      expect(songRow.first['updated_token'], equals(22));
    });
  });

  group('CatalogRepository token ordering', () {
    late Directory testDir;
    late CatalogDatabase catalogDatabase;
    late CatalogRepository repository;

    setUp(() async {
      testDir = await rootTempDir.createTemp('token_ordering_');
      catalogDatabase =
          CatalogDatabase(databasePath: '${testDir.path}/catalog.db');
      catalogDatabase.initialize();
      repository = CatalogRepository(database: catalogDatabase.database);
    });

    tearDown(() async {
      catalogDatabase.close();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('appendChangeEvents and readChangesSince return monotonic token order', () {
      repository.appendChangeEvents(
        <CatalogChangeEventInput>[
          CatalogChangeEventInput(
            entityType: 'song',
            entityId: 'song-1',
            op: 'upsert',
            payloadJson: '{"id":"song-1"}',
            occurredEpochMs: 1700000000000,
          ),
          CatalogChangeEventInput(
            entityType: 'album',
            entityId: 'album-1',
            op: 'upsert',
            payloadJson: '{"id":"album-1"}',
            occurredEpochMs: 1700000001000,
          ),
          CatalogChangeEventInput(
            entityType: 'song',
            entityId: 'song-1',
            op: 'delete',
            payloadJson: null,
            occurredEpochMs: 1700000002000,
          ),
        ],
      );

      final List<CatalogChangeEventRecord> allEvents =
          repository.readChangesSince(0, 10);
      expect(allEvents.length, equals(3));
      expect(allEvents[0].token, lessThan(allEvents[1].token));
      expect(allEvents[1].token, lessThan(allEvents[2].token));
      expect(allEvents.map((event) => event.entityId).toList(),
          equals(<String>['song-1', 'album-1', 'song-1']));

      final int latestToken = repository.getLatestToken();
      expect(latestToken, equals(allEvents.last.token));

      final List<CatalogChangeEventRecord> afterFirst =
          repository.readChangesSince(allEvents.first.token, 1);
      expect(afterFirst.length, equals(1));
      expect(afterFirst.single.token, equals(allEvents[1].token));
    });
  });
}
