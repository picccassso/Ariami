import 'package:ariami_mobile/models/download_task.dart';
import 'package:ariami_mobile/services/download/download_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadTask _task({required String id, required DownloadStatus status}) {
  return DownloadTask(
    id: id,
    songId: 'song-$id',
    title: 'Title $id',
    artist: 'Artist',
    albumArt: 'https://example.com/art.jpg',
    downloadUrl: 'https://example.com/download/$id',
    status: status,
    totalBytes: 1000,
  );
}

void main() {
  group('queueHasActiveDownloads', () {
    test('returns true for pending, downloading, and paused tasks', () {
      expect(
        queueHasActiveDownloads([_task(id: '1', status: DownloadStatus.pending)]),
        isTrue,
      );
      expect(
        queueHasActiveDownloads(
          [_task(id: '2', status: DownloadStatus.downloading)],
        ),
        isTrue,
      );
      expect(
        queueHasActiveDownloads([_task(id: '3', status: DownloadStatus.paused)]),
        isTrue,
      );
    });

    test('returns false when only completed, failed, or cancelled remain', () {
      expect(
        queueHasActiveDownloads(
          [_task(id: '1', status: DownloadStatus.completed)],
        ),
        isFalse,
      );
      expect(
        queueHasActiveDownloads([_task(id: '2', status: DownloadStatus.failed)]),
        isFalse,
      );
      expect(
        queueHasActiveDownloads(
          [_task(id: '3', status: DownloadStatus.cancelled)],
        ),
        isFalse,
      );
    });

    test('stays true when first song completes but another is pending', () {
      expect(
        queueHasActiveDownloads([
          _task(id: '1', status: DownloadStatus.completed),
          _task(id: '2', status: DownloadStatus.pending),
        ]),
        isTrue,
      );
    });
  });

  group('computeSessionDownloadProgress', () {
    test('advances smoothly across a multi-song batch', () {
      const sessionIds = {'1', '2', '3'};
      final queue = [
        _task(id: '1', status: DownloadStatus.completed),
        _task(id: '2', status: DownloadStatus.downloading),
        _task(id: '3', status: DownloadStatus.pending),
      ];

      expect(
        computeSessionDownloadProgress(
          queue: queue,
          sessionTaskIds: sessionIds,
          latestTaskProgress: const {'2': 0.5},
        ),
        closeTo(0.5, 0.001),
      );

      expect(
        computeSessionDownloadProgress(
          queue: [
            _task(id: '1', status: DownloadStatus.completed),
            _task(id: '2', status: DownloadStatus.completed),
            _task(id: '3', status: DownloadStatus.downloading),
          ],
          sessionTaskIds: sessionIds,
          latestTaskProgress: const {'3': 0.25},
        ),
        closeTo(0.75, 0.001),
      );
    });

    test('returns null when no active downloads remain', () {
      expect(
        computeSessionDownloadProgress(
          queue: [_task(id: '1', status: DownloadStatus.completed)],
          sessionTaskIds: const {'1'},
        ),
        isNull,
      );
    });
  });
}
