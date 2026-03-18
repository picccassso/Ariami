import 'package:ariami_mobile/database/library_sync_database.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/services/api/api_client.dart';
import 'package:ariami_mobile/services/library/library_read_facade.dart';
import 'package:ariami_mobile/services/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibraryReadFacade', () {
    test('waits briefly for bootstrap and prefers v2 local store when ready',
        () async {
      final apiClient = _CountingApiClient();
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
        apiClientProvider: () => apiClient,
        libraryRepository: repository,
        useV2SyncStoreOverride: true,
        bootstrapWaitTimeout: const Duration(milliseconds: 20),
        bootstrapPollInterval: const Duration(milliseconds: 1),
      );

      final bundle = await facade.getLibraryBundle();

      expect(bundle.source, LibraryReadSource.v2LocalStore);
      expect(bundle.albums.length, equals(1));
      expect(bundle.songs.length, equals(1));
      expect(bundle.serverPlaylists.length, equals(1));
      expect(apiClient.libraryCalls, equals(0));
    });

    test('falls back to v1 snapshot when bootstrap never completes in time',
        () async {
      final apiClient = _CountingApiClient(
        library: LibraryResponse(
          albums: const <AlbumModel>[],
          songs: const <SongModel>[],
          serverPlaylists: const <ServerPlaylist>[],
          lastUpdated: '2026-03-17T00:00:00Z',
          durationsReady: true,
        ),
      );
      final repository = _FlippingBootstrapRepository(
        completeAfterChecks: 999,
        bundle: const LibraryRepositoryBundle(
          albums: <AlbumModel>[],
          songs: <SongModel>[],
          serverPlaylists: <ServerPlaylist>[],
        ),
      );

      final facade = LibraryReadFacade(
        apiClientProvider: () => apiClient,
        libraryRepository: repository,
        useV2SyncStoreOverride: true,
        bootstrapWaitTimeout: const Duration(milliseconds: 5),
        bootstrapPollInterval: const Duration(milliseconds: 1),
      );

      final bundle = await facade.getLibraryBundle();

      expect(bundle.source, LibraryReadSource.v1Snapshot);
      expect(apiClient.libraryCalls, equals(1));
    });

    test(
        'hydrates server playlists from v1 when v2 local store lacks playlist song membership',
        () async {
      final apiClient = _CountingApiClient(
        library: LibraryResponse(
          albums: const <AlbumModel>[],
          songs: const <SongModel>[],
          serverPlaylists: <ServerPlaylist>[
            ServerPlaylist(
              id: 'playlist-1',
              name: 'Playlist 1',
              songIds: <String>['song-1', 'song-2'],
              songCount: 2,
            ),
          ],
          lastUpdated: '2026-03-17T00:00:00Z',
          durationsReady: true,
        ),
      );
      final repository = _FlippingBootstrapRepository(
        completeAfterChecks: 0,
        bundle: LibraryRepositoryBundle(
          albums: const <AlbumModel>[],
          songs: const <SongModel>[],
          serverPlaylists: <ServerPlaylist>[
            ServerPlaylist(
              id: 'playlist-1',
              name: 'Playlist 1',
              songIds: const <String>[],
              songCount: 2,
            ),
          ],
        ),
      );

      final facade = LibraryReadFacade(
        apiClientProvider: () => apiClient,
        libraryRepository: repository,
        useV2SyncStoreOverride: true,
        bootstrapWaitTimeout: Duration.zero,
      );

      final bundle = await facade.getLibraryBundle();

      expect(bundle.source, LibraryReadSource.v2LocalStore);
      expect(bundle.serverPlaylists.single.songIds, ['song-1', 'song-2']);
      expect(apiClient.libraryCalls, equals(1));
      expect(bundle.sourceReason, contains('hydrated from v1 snapshot'));
    });
  });
}

class _CountingApiClient extends ApiClient {
  _CountingApiClient({LibraryResponse? library})
      : _library = library ??
            LibraryResponse(
              albums: const <AlbumModel>[],
              songs: const <SongModel>[],
              serverPlaylists: const <ServerPlaylist>[],
              lastUpdated: '2026-03-17T00:00:00Z',
              durationsReady: true,
            ),
        super(
          serverInfo: ServerInfo(
            server: '127.0.0.1',
            port: 8080,
            name: 'test',
            version: 'test',
          ),
        );

  final LibraryResponse _library;
  int libraryCalls = 0;

  @override
  Future<LibraryResponse> getLibrary() async {
    libraryCalls++;
    return _library;
  }
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
