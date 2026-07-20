import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/download_task.dart';
import 'package:ariami_mobile/screens/main/library/library_controller.dart';
import 'package:ariami_mobile/screens/main/library/library_state.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_support/sqflite_mock.dart';

void main() {
  setUpAll(() async {
    installSqfliteTestMocks();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initializeSharedPrefs();
  });

  tearDownAll(uninstallSqfliteTestMocks);

  group('LibraryController load scheduling', () {
    late LibraryController controller;

    setUp(() {
      controller = LibraryController();
      controller.resetLoadSchedulingForTest();
    });

    test('queues deferred reload when library load is already in flight',
        () async {
      controller.markLibraryLoadInFlightForTest();

      await controller.loadLibraryForTest(background: true);

      expect(controller.isLibraryLoadInFlightForTest, isTrue);
      expect(controller.pendingBackgroundReloadForTest, isTrue);
    });

    test('chains a background reload after the in-flight load completes',
        () async {
      controller.markLibraryLoadInFlightForTest();
      await controller.loadLibraryForTest(background: true);

      await controller.completeLibraryLoadForTest();
      await Future<void>.delayed(Duration.zero);

      expect(controller.pendingBackgroundReloadForTest, isFalse);
      expect(controller.libraryLoadAttemptsForTest, equals(1));
    });

    test('defers sync-token refresh while load is in flight', () async {
      controller.markLibraryLoadInFlightForTest();

      final refreshed = await controller.refreshFromSyncTokenForTest(42);

      expect(refreshed, isFalse);
      expect(controller.pendingBackgroundReloadForTest, isTrue);
    });

    test('does not mark sync token handled when refresh is deferred', () async {
      controller.markLibraryLoadInFlightForTest();

      await controller.handleSyncTokenAdvancedForTest(42);

      expect(controller.lastHandledSyncTokenForTest, equals(0));
    });
  });

  test('settled download queue rebuilds albums and songs while offline',
      () async {
    final controller = LibraryController();
    await controller.offlineService.setManualOfflineMode(true);
    addTearDown(
      () => controller.offlineService.setManualOfflineMode(false),
    );
    controller.setStateForTest(const LibraryState(isLoading: false));

    await controller.refreshDownloadedLibraryForTest([
      _completedDownload(
        songId: 'album-song',
        title: 'Album Song',
        albumId: 'album-1',
      ),
      _completedDownload(
        songId: 'standalone-song',
        title: 'Standalone Song',
      ),
    ]);

    expect(controller.state.albums.map((album) => album.id), ['album-1']);
    expect(
      controller.state.offlineSongs.map((song) => song.id),
      ['standalone-song'],
    );
    expect(
      controller.state.downloadedSongIds,
      {'album-song', 'standalone-song'},
    );
    expect(controller.state.albumsWithDownloads, {'album-1'});
  });

  group('Batch download summary', () {
    late LibraryController controller;

    setUp(() {
      controller = LibraryController();
      controller.resetBatchDownloadTestState();
    });

    test('all selected songs downloaded marks batch as allSaved', () {
      controller.setStateForTest(const LibraryState(
        isLoading: false,
        downloadedSongIds: {'song-1', 'song-2'},
      ));
      controller.setSelectionForTest(songIds: {'song-1', 'song-2'});

      final summary = controller.computeBatchDownloadSummaryForTest();

      expect(summary.allSaved, isTrue);
      expect(summary.toDownloadCount, 0);
      expect(summary.alreadySavedCount, 2);
    });

    test('mixed selection computes partial skip counts', () {
      controller.setStateForTest(LibraryState(
        isLoading: false,
        downloadedSongIds: {'song-1'},
        songs: [
          SongModel(
            id: 'song-1',
            title: 'A',
            artist: 'X',
            duration: 100,
          ),
          SongModel(
            id: 'song-2',
            title: 'B',
            artist: 'X',
            duration: 100,
          ),
        ],
      ));
      controller.setSelectionForTest(songIds: {'song-1', 'song-2'});

      final summary = controller.computeBatchDownloadSummaryForTest();

      expect(summary.allSaved, isFalse);
      expect(summary.hasPartialSkip, isTrue);
      expect(summary.toDownloadCount, 1);
      expect(summary.alreadySavedCount, 1);
    });

    test('fully downloaded album is allSaved', () {
      const albumId = 'album-1';
      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: [
          AlbumModel(
            id: albumId,
            title: 'Album',
            artist: 'A',
            songCount: 2,
            duration: 200,
          ),
        ],
        songs: [
          SongModel(
            id: 'song-1',
            title: 'T1',
            artist: 'A',
            albumId: albumId,
            duration: 100,
          ),
          SongModel(
            id: 'song-2',
            title: 'T2',
            artist: 'A',
            albumId: albumId,
            duration: 100,
          ),
        ],
        downloadedSongIds: {'song-1', 'song-2'},
        fullyDownloadedAlbumIds: {albumId},
      ));
      controller.setSelectionForTest(albumIds: {albumId});

      final summary = controller.computeBatchDownloadSummaryForTest();

      expect(summary.allSaved, isTrue);
      expect(summary.toDownloadCount, 0);
    });

    test('partially downloaded album counts only missing songs', () {
      const albumId = 'album-1';
      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: [
          AlbumModel(
            id: albumId,
            title: 'Album',
            artist: 'A',
            songCount: 2,
            duration: 200,
          ),
        ],
        songs: [
          SongModel(
            id: 'song-1',
            title: 'T1',
            artist: 'A',
            albumId: albumId,
            duration: 100,
          ),
          SongModel(
            id: 'song-2',
            title: 'T2',
            artist: 'A',
            albumId: albumId,
            duration: 100,
          ),
        ],
        downloadedSongIds: {'song-1'},
      ));
      controller.setSelectionForTest(albumIds: {albumId});

      final summary = controller.computeBatchDownloadSummaryForTest();

      expect(summary.allSaved, isFalse);
      expect(summary.toDownloadCount, 1);
      expect(summary.hasPartialSkip, isTrue);
    });

    test('song in queue is not counted in toDownloadCount', () {
      controller.setStateForTest(const LibraryState(isLoading: false));
      controller.queuedSongIdsForTest = {'song-1'};
      controller.setSelectionForTest(songIds: {'song-1'});

      final summary = controller.computeBatchDownloadSummaryForTest();

      expect(summary.inQueueCount, 1);
      expect(summary.toDownloadCount, 0);
      expect(summary.allSaved, isTrue);
    });

    test('downloadSelectedItems keeps selection when all saved', () async {
      controller.setStateForTest(const LibraryState(
        isLoading: false,
        downloadedSongIds: {'song-1'},
      ));
      controller.setSelectionForTest(songIds: {'song-1'});

      final count = await controller.downloadSelectedItems();

      expect(count, 0);
      expect(controller.isSelectionModeActive, isTrue);
      expect(controller.totalSelectedCount, 1);
    });
  });
}

DownloadTask _completedDownload({
  required String songId,
  required String title,
  String? albumId,
}) {
  return DownloadTask(
    id: 'song_$songId',
    songId: songId,
    title: title,
    artist: 'Artist',
    albumId: albumId,
    albumName: albumId == null ? null : 'Album',
    albumArtist: albumId == null ? null : 'Album Artist',
    albumArt: '',
    downloadUrl: '',
    status: DownloadStatus.completed,
    bytesDownloaded: 100,
    totalBytes: 100,
  );
}
