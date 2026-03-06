import 'package:ariami_mobile/database/library_sync_database.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/services/api/api_client.dart';
import 'package:ariami_mobile/services/library/library_read_facade.dart';
import 'package:ariami_mobile/services/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Downloads screen data-source compatibility', () {
    test(
      'v1 compatibility mode + empty v2 store does not resolve false 0/0 song-album totals',
      () async {
        final facade = LibraryReadFacade(
          apiClientProvider: () => _FakeApiClient(
            library: LibraryResponse(
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
              serverPlaylists: const <ServerPlaylist>[],
              lastUpdated: '2026-02-07T00:00:00Z',
              durationsReady: true,
            ),
          ),
          libraryRepository: _EmptyV2Repository(),
          useV2SyncStoreOverride: true,
        );

        final bundle = await facade.getLibraryBundle();

        expect(bundle.source, LibraryReadSource.v1Snapshot);
        expect(bundle.songs.length, greaterThan(0));
        expect(bundle.albums.length, greaterThan(0));
      },
    );
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required this.library})
      : super(
          serverInfo: ServerInfo(
            server: '127.0.0.1',
            port: 8080,
            name: 'test',
            version: 'test',
          ),
        );

  final LibraryResponse library;

  @override
  Future<LibraryResponse> getLibrary() async => library;
}

class _EmptyV2Repository extends LibraryRepository {
  _EmptyV2Repository() : super(database: _FakeLibrarySyncDatabase());

  @override
  Future<bool> hasCompletedBootstrap() async => false;
}

class _FakeLibrarySyncDatabase extends LibrarySyncDatabase {}
