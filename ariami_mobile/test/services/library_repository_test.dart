import 'package:ariami_mobile/database/library_sync_database.dart';
import 'package:ariami_mobile/services/library/library_repository.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    final dbPath = p.join(await getDatabasesPath(), 'library_sync.db');
    await deleteDatabase(dbPath);
  });

  group('LibraryRepository', () {
    test('bootstrap stores playlists with playlist-song membership', () async {
      final repository = LibraryRepository();
      addTearDown(repository.close);

      await repository.applyBootstrapPage(
        V2BootstrapResponse(
          syncToken: 4,
          albums: <AlbumModel>[
            AlbumModel(
              id: 'album-1',
              title: 'Album 1',
              artist: 'Artist 1',
              songCount: 2,
              duration: 360,
            ),
          ],
          songs: <SongModel>[
            SongModel(
              id: 'song-1',
              title: 'Song 1',
              artist: 'Artist 1',
              albumId: 'album-1',
              duration: 180,
              trackNumber: 1,
            ),
            SongModel(
              id: 'song-2',
              title: 'Song 2',
              artist: 'Artist 1',
              albumId: 'album-1',
              duration: 180,
              trackNumber: 2,
            ),
          ],
          playlists: const <V2PlaylistModel>[
            V2PlaylistModel(
              id: 'playlist-1',
              name: 'Playlist 1',
              songCount: 2,
              duration: 0,
              songIds: <String>['song-2', 'song-1'],
            ),
          ],
          pageInfo: V2PageInfo(
            cursor: null,
            nextCursor: null,
            hasMore: false,
            limit: 200,
          ),
        ),
      );
      await repository.completeBootstrap(lastAppliedToken: 4);

      final playlists = await repository.getServerPlaylists();
      expect(playlists.length, equals(1));
      expect(playlists.single.songIds, equals(<String>['song-2', 'song-1']));
    });

    test('delta sync updates playlist metadata and membership ordering',
        () async {
      final repository = LibraryRepository();
      addTearDown(repository.close);

      await repository.applyBootstrapPage(
        V2BootstrapResponse(
          syncToken: 4,
          albums: const <AlbumModel>[],
          songs: <SongModel>[
            SongModel(
              id: 'song-1',
              title: 'Song 1',
              artist: 'Artist 1',
              albumId: null,
              duration: 180,
            ),
            SongModel(
              id: 'song-2',
              title: 'Song 2',
              artist: 'Artist 2',
              albumId: null,
              duration: 200,
            ),
          ],
          playlists: const <V2PlaylistModel>[
            V2PlaylistModel(
              id: 'playlist-1',
              name: 'Playlist 1',
              songCount: 1,
              duration: 0,
              songIds: <String>['song-1'],
            ),
          ],
          pageInfo: V2PageInfo(
            cursor: null,
            nextCursor: null,
            hasMore: false,
            limit: 200,
          ),
        ),
      );
      await repository.completeBootstrap(lastAppliedToken: 4);

      await repository.applyChangesResponse(
        V2ChangesResponse(
          fromToken: 4,
          toToken: 7,
          events: const <V2ChangeEvent>[
            V2ChangeEvent(
              token: 5,
              op: V2ChangeOp.upsert,
              entityType: V2EntityType.playlist,
              entityId: 'playlist-1',
              payload: <String, dynamic>{
                'id': 'playlist-1',
                'name': 'Renamed Playlist',
                'songCount': 1,
                'duration': 0,
                'songIds': <String>['song-2'],
              },
              occurredAt: '2026-04-04T10:00:00Z',
            ),
            V2ChangeEvent(
              token: 6,
              op: V2ChangeOp.delete,
              entityType: V2EntityType.playlistSong,
              entityId: 'playlist-1:song-1',
              payload: <String, dynamic>{
                'playlistId': 'playlist-1',
                'songId': 'song-1',
              },
              occurredAt: '2026-04-04T10:00:01Z',
            ),
            V2ChangeEvent(
              token: 7,
              op: V2ChangeOp.upsert,
              entityType: V2EntityType.playlistSong,
              entityId: 'playlist-1:song-2',
              payload: <String, dynamic>{
                'playlistId': 'playlist-1',
                'songId': 'song-2',
                'position': 0,
              },
              occurredAt: '2026-04-04T10:00:02Z',
            ),
          ],
          hasMore: false,
          syncToken: 7,
        ),
      );

      final playlists = await repository.getServerPlaylists();
      expect(playlists.single.name, equals('Renamed Playlist'));
      expect(playlists.single.songIds, equals(<String>['song-2']));
    });

    test(
        'treats legacy playlists without playlist-song rows as bootstrap-incomplete',
        () async {
      final database = await LibrarySyncDatabase.create();
      final repository = LibraryRepository(database: database);
      addTearDown(repository.close);

      await database.upsertPlaylists(
        const <LibraryPlaylistRow>[
          LibraryPlaylistRow(
            id: 'playlist-1',
            name: 'Playlist 1',
            songCount: 2,
            duration: 0,
          ),
        ],
      );
      await database.saveSyncState(
        const LibrarySyncState(
          lastAppliedToken: 9,
          bootstrapComplete: true,
          lastSyncEpochMs: 0,
        ),
      );

      expect(await repository.hasCompletedBootstrap(), isFalse);

      await database.upsertPlaylistSongs(
        const <LibraryPlaylistSongRow>[
          LibraryPlaylistSongRow(
            playlistId: 'playlist-1',
            songId: 'song-1',
            position: 0,
          ),
          LibraryPlaylistSongRow(
            playlistId: 'playlist-1',
            songId: 'song-2',
            position: 1,
          ),
        ],
      );

      expect(await repository.hasCompletedBootstrap(), isTrue);
    });
  });
}
