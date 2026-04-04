import 'package:ariami_mobile/database/library_sync_database.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/library/library_read_facade.dart';
import 'package:ariami_mobile/services/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibraryReadFacade', () {
    test('waits briefly for bootstrap and serves v2 local store when ready',
        () async {
      final repository = _FlippingBootstrapRepository(
        completeAfterChecks: 1,
        bundle: LibraryRepositoryBundle(
          albums: [
            AlbumModel(
              id: 'album-1',
              title: 'Album 1',
              artist: 'Artist 1',
              songCount: 1,
              duration: 180,
            ),
          ],
          songs: [
            SongModel(
              id: 'song-1',
              title: 'Song 1',
              artist: 'Artist 1',
              albumId: 'album-1',
              duration: 180,
              trackNumber: 1,
            ),
          ],
          serverPlaylists: [
            ServerPlaylist(
              id: 'playlist-1',
              name: 'Playlist 1',
              songIds: ['song-1'],
              songCount: 1,
            ),
          ],
        ),
      );

      final facade = LibraryReadFacade(
        apiClientProvider: () => Object(),
        libraryRepository: repository,
        bootstrapWaitTimeout: const Duration(milliseconds: 20),
        bootstrapPollInterval: const Duration(milliseconds: 1),
      );

      final bundle = await facade.getLibraryBundle();

      expect(bundle.source, LibraryReadSource.v2LocalStore);
      expect(bundle.albums.length, equals(1));
      expect(bundle.songs.length, equals(1));
      expect(bundle.serverPlaylists.single.songIds, equals(['song-1']));
      expect(bundle.sourceReason, contains('bootstrap is complete'));
    });

    test('serves existing v2 snapshot while bootstrap is still in progress',
        () async {
      final repository = _FlippingBootstrapRepository(
        completeAfterChecks: 999,
        bundle: LibraryRepositoryBundle(
          albums: [
            AlbumModel(
              id: 'album-1',
              title: 'Album 1',
              artist: 'Artist 1',
              songCount: 2,
              duration: 360,
            ),
          ],
          songs: [
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
          serverPlaylists: const <ServerPlaylist>[],
        ),
      );

      final facade = LibraryReadFacade(
        apiClientProvider: () => Object(),
        libraryRepository: repository,
        bootstrapWaitTimeout: const Duration(milliseconds: 5),
        bootstrapPollInterval: const Duration(milliseconds: 1),
      );

      final bundle = await facade.getLibraryBundle();

      expect(bundle.source, LibraryReadSource.v2LocalStore);
      expect(bundle.songs.length, equals(2));
      expect(bundle.sourceReason, contains('bootstrap is still in progress'));
    });

    test('returns server playlists directly from local v2 playlist membership',
        () async {
      final repository = _FlippingBootstrapRepository(
        completeAfterChecks: 0,
        bundle: LibraryRepositoryBundle(
          albums: const <AlbumModel>[],
          songs: const <SongModel>[],
          serverPlaylists: <ServerPlaylist>[
            ServerPlaylist(
              id: 'playlist-1',
              name: 'Playlist 1',
              songIds: const <String>['song-1', 'song-2'],
              songCount: 2,
            ),
          ],
        ),
      );

      final facade = LibraryReadFacade(
        apiClientProvider: () => Object(),
        libraryRepository: repository,
        bootstrapWaitTimeout: Duration.zero,
      );

      final bundle = await facade.getLibraryBundle();

      expect(bundle.source, LibraryReadSource.v2LocalStore);
      expect(bundle.serverPlaylists.single.songIds, ['song-1', 'song-2']);
    });

    test('builds album detail from local v2 album and song rows', () async {
      final repository = _AlbumDetailRepository();
      final facade = LibraryReadFacade(
        apiClientProvider: () => Object(),
        libraryRepository: repository,
      );

      final detail = await facade.getAlbumDetail('album-1');

      expect(detail, isNotNull);
      expect(detail!.id, equals('album-1'));
      expect(detail.coverArt, equals('/art/album-1'));
      expect(detail.songs.map((song) => song.id).toList(), equals(['song-1']));
    });
  });
}

class _FlippingBootstrapRepository extends LibraryRepository {
  _FlippingBootstrapRepository({
    required this.completeAfterChecks,
    required this.bundle,
  }) : super(database: _FakeLibrarySyncDatabase());

  final int completeAfterChecks;
  final LibraryRepositoryBundle bundle;

  int _checkCount = 0;

  @override
  Future<bool> hasCompletedBootstrap() async {
    _checkCount++;
    return _checkCount > completeAfterChecks;
  }

  @override
  Future<LibraryRepositoryBundle> getLibraryBundle() async => bundle;
}

class _FakeLibrarySyncDatabase extends LibrarySyncDatabase {}

class _AlbumDetailRepository extends LibraryRepository {
  _AlbumDetailRepository() : super(database: _FakeLibrarySyncDatabase());

  @override
  Future<bool> hasCompletedBootstrap() async => true;

  @override
  Future<AlbumModel?> getAlbumById(String albumId) async {
    return AlbumModel(
      id: albumId,
      title: 'Album 1',
      artist: 'Artist 1',
      coverArt: '/art/album-1',
      songCount: 1,
      duration: 180,
    );
  }

  @override
  Future<List<SongModel>> getSongsByAlbumId(String albumId) async {
    return <SongModel>[
      SongModel(
        id: 'song-1',
        title: 'Song 1',
        artist: 'Artist 1',
        albumId: albumId,
        duration: 180,
        trackNumber: 1,
      ),
    ];
  }
}
