import 'package:ariami_mobile/models/download_task.dart';
import 'package:ariami_mobile/widgets/download/collection_download_button.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadTask task({
  required String songId,
  required DownloadStatus status,
  double progress = 0,
}) {
  return DownloadTask(
    id: 'song_$songId',
    songId: songId,
    title: 'Song $songId',
    artist: 'Artist',
    albumArt: '',
    downloadUrl: '',
    status: status,
    progress: progress,
    totalBytes: 100,
  );
}

void main() {
  group('calculateCollectionDownloadState', () {
    test('combines completed, active, and pending song progress', () {
      final state = calculateCollectionDownloadState(
        songIds: const ['one', 'two', 'three'],
        tasks: [
          task(songId: 'one', status: DownloadStatus.completed),
          task(
            songId: 'two',
            status: DownloadStatus.downloading,
            progress: 0.5,
          ),
          task(songId: 'three', status: DownloadStatus.pending),
        ],
      );

      expect(state.completed, 1);
      expect(state.inProgress, isTrue);
      expect(state.progress, closeTo(0.5, 0.001));
    });

    test('uses the latest streamed progress for a running task', () {
      final state = calculateCollectionDownloadState(
        songIds: const ['one'],
        tasks: [
          task(
            songId: 'one',
            status: DownloadStatus.downloading,
            progress: 0.2,
          ),
        ],
        latestTaskProgress: const {'song_one': 0.75},
      );

      expect(state.inProgress, isTrue);
      expect(state.progress, closeTo(0.75, 0.001));
    });

    test('does not show failed or cancelled tasks as active', () {
      final state = calculateCollectionDownloadState(
        songIds: const ['one', 'two'],
        tasks: [
          task(songId: 'one', status: DownloadStatus.failed, progress: 0.8),
          task(songId: 'two', status: DownloadStatus.cancelled, progress: 0.4),
        ],
      );

      expect(state.completed, 0);
      expect(state.inProgress, isFalse);
      expect(state.progress, 0);
    });
  });
}
