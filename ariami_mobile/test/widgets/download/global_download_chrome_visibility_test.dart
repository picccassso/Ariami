import 'package:ariami_mobile/models/download_task.dart';
import 'package:ariami_mobile/services/download/download_helpers.dart';
import 'package:ariami_mobile/services/download/download_manager.dart';
import 'package:ariami_mobile/widgets/download/global_download_chrome_visibility.dart';
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
  tearDown(() {
    GlobalDownloadChromeVisibility.instance.debugReset();
    DownloadManager().sessionTaskIds.clear();
  });

  group('GlobalDownloadChromeVisibility', () {
    test('shows bar for active session and hides when session ends', () {
      final visibility = GlobalDownloadChromeVisibility.instance;

      visibility.debugApplyQueue([
        _task(id: '1', status: DownloadStatus.downloading),
      ]);
      expect(visibility.isBarVisible, isTrue);

      visibility.debugApplyQueue([
        _task(id: '1', status: DownloadStatus.completed),
        _task(id: '2', status: DownloadStatus.pending),
      ]);
      expect(visibility.isBarVisible, isTrue);

      visibility.debugApplyQueue([
        _task(id: '1', status: DownloadStatus.completed),
        _task(id: '2', status: DownloadStatus.completed),
      ]);
      expect(visibility.isBarVisible, isFalse);
    });

    test('does not notify listeners when visibility is unchanged', () {
      final visibility = GlobalDownloadChromeVisibility.instance;
      var notificationCount = 0;
      visibility.addListener(() => notificationCount++);

      visibility.debugApplyQueue([
        _task(id: '1', status: DownloadStatus.downloading),
      ]);
      expect(notificationCount, 1);

      visibility.debugApplyQueue([
        _task(id: '1', status: DownloadStatus.downloading),
        _task(id: '2', status: DownloadStatus.pending),
      ]);
      expect(notificationCount, 1);
    });

    test('tracks aggregate session progress across multiple songs', () {
      final visibility = GlobalDownloadChromeVisibility.instance;
      DownloadManager().sessionTaskIds.addAll(['1', '2']);

      visibility.debugApplyQueue([
        _task(id: '1', status: DownloadStatus.completed),
        _task(id: '2', status: DownloadStatus.downloading),
      ]);

      expect(visibility.sessionProgress, closeTo(0.5, 0.001));

      visibility.debugApplyQueue([
        _task(id: '1', status: DownloadStatus.completed),
        _task(id: '2', status: DownloadStatus.completed),
      ]);

      expect(visibility.isBarVisible, isFalse);
      expect(visibility.sessionProgress, isNull);
    });
  });
}
