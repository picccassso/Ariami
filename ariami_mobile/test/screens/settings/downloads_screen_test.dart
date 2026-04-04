import 'package:ariami_mobile/database/library_sync_database.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/library/library_read_facade.dart';
import 'package:ariami_mobile/services/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Downloads screen data-source compatibility', () {
    test(
      'v2 local snapshot remains usable while bootstrap is incomplete',
      () async {
        final facade = LibraryReadFacade(
          apiClientProvider: () => Object(),
          libraryRepository: _SnapshotWhileBootstrappingRepository(),
        );

        final bundle = await facade.getLibraryBundle();

        expect(bundle.source, LibraryReadSource.v2LocalStore);
        expect(bundle.songs.length, greaterThan(0));
        expect(bundle.albums.length, greaterThan(0));
      },
    );
  });
}

class _SnapshotWhileBootstrappingRepository extends LibraryRepository {
  _SnapshotWhileBootstrappingRepository()
      : super(database: _FakeLibrarySyncDatabase());

  @override
  Future<bool> hasCompletedBootstrap() async => false;

  @override
  Future<LibraryRepositoryBundle> getLibraryBundle() async {
    return LibraryRepositoryBundle(
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
    );
  }
}

class _FakeLibrarySyncDatabase extends LibrarySyncDatabase {}
