import '../../../../models/download_task.dart';

/// Group completed downloads by album id (`null` = singles).
Map<String?, List<DownloadTask>> groupByAlbum(List<DownloadTask> tasks) {
  final Map<String?, List<DownloadTask>> grouped = {};
  for (final task in tasks) {
    final key = task.albumId;
    grouped.putIfAbsent(key, () => []).add(task);
  }
  for (final songs in grouped.values) {
    songs.sort(
      (a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0),
    );
  }
  return grouped;
}

int calculateTotalBytes(List<DownloadTask> tasks) {
  return tasks.fold<int>(
    0,
    (sum, task) => sum + task.bytesDownloaded,
  );
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
