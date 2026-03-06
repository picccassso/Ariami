import 'dart:io';

import 'package:ariami_core/models/download_job_models.dart';
import 'package:ariami_core/services/catalog/catalog_database.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/library/library_manager.dart';
import 'package:ariami_core/services/server/download_job_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Phase 9 - DownloadJobService', () {
    late Directory tempDir;
    late CatalogDatabase catalogDatabase;
    late CatalogRepository repository;
    late LibraryManager libraryManager;
    late DownloadJobService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_phase9_djsvc_');
      catalogDatabase = CatalogDatabase(
        databasePath: p.join(tempDir.path, 'catalog.db'),
      );
      catalogDatabase.initialize();
      repository = CatalogRepository(database: catalogDatabase.database);
      libraryManager = LibraryManager();
      libraryManager.clear();
      _seedCatalog(repository);

      service = DownloadJobService(
        catalogRepositoryProvider: () => repository,
        libraryManager: libraryManager,
      );
    });

    tearDown(() async {
      catalogDatabase.close();
      libraryManager.clear();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('create/status/items/cancel flow and user scope guard', () {
      final created = service.createJob(
        userScopeId: 'user-1',
        request: const DownloadJobCreateRequest(
          songIds: <String>['song-a', 'song-b'],
          albumIds: <String>['album-b'],
          quality: 'high',
          downloadOriginal: false,
        ),
      );

      expect(created.status, equals(DownloadJobStatus.ready));
      expect(created.itemCount, equals(2));
      expect(created.quality, equals('high'));

      final statusBeforeCancel = service.getJob(
        userScopeId: 'user-1',
        jobId: created.jobId,
      );
      expect(statusBeforeCancel.status, equals(DownloadJobStatus.ready));
      expect(statusBeforeCancel.pendingCount, equals(2));
      expect(statusBeforeCancel.cancelledCount, equals(0));

      final pageOne = service.getJobItems(
        userScopeId: 'user-1',
        jobId: created.jobId,
        limit: 1,
      );
      expect(pageOne.items.length, equals(1));
      expect(pageOne.items.first.songId, equals('song-a'));
      expect(pageOne.pageInfo.hasMore, isTrue);
      expect(pageOne.pageInfo.nextCursor, equals('0'));

      final pageTwo = service.getJobItems(
        userScopeId: 'user-1',
        jobId: created.jobId,
        cursor: 0,
        limit: 1,
      );
      expect(pageTwo.items.length, equals(1));
      expect(pageTwo.items.first.songId, equals('song-b'));
      expect(pageTwo.pageInfo.hasMore, isFalse);
      expect(pageTwo.pageInfo.nextCursor, isNull);

      final cancelled = service.cancelJob(
        userScopeId: 'user-1',
        jobId: created.jobId,
      );
      expect(cancelled.status, equals(DownloadJobStatus.cancelled));

      final statusAfterCancel = service.getJob(
        userScopeId: 'user-1',
        jobId: created.jobId,
      );
      expect(statusAfterCancel.status, equals(DownloadJobStatus.cancelled));
      expect(statusAfterCancel.pendingCount, equals(0));
      expect(statusAfterCancel.cancelledCount, equals(2));

      expect(
        () => service.getJob(
          userScopeId: 'user-2',
          jobId: created.jobId,
        ),
        throwsA(
          isA<DownloadJobServiceException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.code, 'code', DownloadJobErrorCodes.jobNotFound),
        ),
      );
    });
  });
}

void _seedCatalog(CatalogRepository repository) {
  repository.upsertAlbum(
    CatalogAlbumRecord(
      id: 'album-a',
      title: 'Album A',
      artist: 'Artist A',
      year: 2021,
      coverArtKey: 'album-a',
      songCount: 1,
      durationSeconds: 120,
      updatedToken: 1,
    ),
  );
  repository.upsertAlbum(
    CatalogAlbumRecord(
      id: 'album-b',
      title: 'Album B',
      artist: 'Artist B',
      year: 2022,
      coverArtKey: 'album-b',
      songCount: 1,
      durationSeconds: 180,
      updatedToken: 2,
    ),
  );

  repository.upsertSong(
    CatalogSongRecord(
      id: 'song-a',
      filePath: '/tmp/song-a.mp3',
      title: 'Song A',
      artist: 'Artist A',
      albumId: 'album-a',
      durationSeconds: 120,
      trackNumber: 1,
      fileSizeBytes: 1000,
      modifiedEpochMs: 100,
      artworkKey: 'album-a',
      updatedToken: 3,
    ),
  );
  repository.upsertSong(
    CatalogSongRecord(
      id: 'song-b',
      filePath: '/tmp/song-b.mp3',
      title: 'Song B',
      artist: 'Artist B',
      albumId: 'album-b',
      durationSeconds: 180,
      trackNumber: 1,
      fileSizeBytes: 1001,
      modifiedEpochMs: 101,
      artworkKey: 'album-b',
      updatedToken: 4,
    ),
  );
}
