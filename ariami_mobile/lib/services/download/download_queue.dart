import 'dart:async';
import '../../models/download_task.dart';

/// Manages the download queue with priority and order
class DownloadQueue {
  final List<DownloadTask> _queue = [];
  final StreamController<List<DownloadTask>> _queueController =
      StreamController<List<DownloadTask>>.broadcast();

  /// Stream of queue changes
  Stream<List<DownloadTask>> get queueStream => _queueController.stream;

  /// Get current queue
  List<DownloadTask> get queue => List.unmodifiable(_queue);

  /// Get queue length
  int get length => _queue.length;

  /// Check if queue is empty
  bool get isEmpty => _queue.isEmpty;

  /// Add task to queue
  void enqueue(DownloadTask task) {
    _queue.add(task);
    _notifyListeners();
  }

  /// Add multiple tasks to queue
  void enqueueBatch(List<DownloadTask> tasks) {
    _queue.addAll(tasks);
    _notifyListeners();
  }

  /// Remove task from queue
  void dequeue(String taskId) {
    _queue.removeWhere((task) => task.id == taskId);
    _notifyListeners();
  }

  /// Remove tasks matching a predicate
  void dequeueWhere(bool Function(DownloadTask) predicate) {
    _queue.removeWhere(predicate);
    _notifyListeners();
  }

  /// Remove all tasks with given status
  void removeByStatus(DownloadStatus status) {
    _queue.removeWhere((task) => task.status == status);
    _notifyListeners();
  }

  /// Get task by ID
  DownloadTask? getTask(String taskId) {
    try {
      return _queue.firstWhere((task) => task.id == taskId);
    } catch (e) {
      return null;
    }
  }

  /// Update task (in-place modification)
  void updateTask(DownloadTask task) {
    final index = _queue.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      _queue[index] = task;
      _notifyListeners();
    }
  }

  /// Get next pending task
  DownloadTask? getNextPending() {
    try {
      return _queue.firstWhere((task) => task.status == DownloadStatus.pending);
    } catch (e) {
      return null;
    }
  }

  /// Get all active downloads (downloading, paused)
  List<DownloadTask> getActiveDownloads() {
    return _queue
        .where((task) =>
            task.status == DownloadStatus.downloading ||
            task.status == DownloadStatus.paused)
        .toList();
  }

  /// Get all completed downloads
  List<DownloadTask> getCompletedDownloads() {
    return _queue
        .where((task) => task.status == DownloadStatus.completed)
        .toList();
  }

  /// Get all failed downloads
  List<DownloadTask> getFailedDownloads() {
    return _queue
        .where((task) => task.status == DownloadStatus.failed)
        .toList();
  }

  /// Get downloads by status
  List<DownloadTask> getTasksByStatus(DownloadStatus status) {
    return _queue.where((task) => task.status == status).toList();
  }

  /// Clear entire queue
  void clear() {
    _queue.clear();
    _notifyListeners();
  }

  /// Get queue statistics
  QueueStats getStats() {
    int totalTasks = _queue.length;
    int completed = _queue.where((t) => t.status == DownloadStatus.completed).length;
    int downloading = _queue.where((t) => t.status == DownloadStatus.downloading).length;
    int failed = _queue.where((t) => t.status == DownloadStatus.failed).length;
    int paused = _queue.where((t) => t.status == DownloadStatus.paused).length;

    int totalBytes = 0;
    int downloadedBytes = 0;

    for (final task in _queue) {
      totalBytes += task.totalBytes;
      if (task.status == DownloadStatus.completed) {
        downloadedBytes += task.bytesDownloaded;
      } else {
        downloadedBytes += task.bytesDownloaded;
      }
    }

    return QueueStats(
      totalTasks: totalTasks,
      completed: completed,
      downloading: downloading,
      failed: failed,
      paused: paused,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
    );
  }

  /// Notify listeners of queue changes
  void _notifyListeners() {
    _queueController.add(List.unmodifiable(_queue));
  }

  /// Dispose resources
  void dispose() {
    _queueController.close();
  }
}

/// Statistics about the download queue
class QueueStats {
  final int totalTasks;
  final int completed;
  final int downloading;
  final int failed;
  final int paused;
  final int totalBytes;
  final int downloadedBytes;

  QueueStats({
    required this.totalTasks,
    required this.completed,
    required this.downloading,
    required this.failed,
    required this.paused,
    required this.totalBytes,
    required this.downloadedBytes,
  });

  /// Get overall progress (0.0 to 1.0)
  double getOverallProgress() {
    if (totalBytes == 0) return 0.0;
    return downloadedBytes / totalBytes;
  }

  /// Get percentage for UI display
  int getOverallPercentage() {
    return (getOverallProgress() * 100).toInt();
  }

  /// Check if any downloads are active
  bool get hasActiveDownloads => downloading > 0 || paused > 0;
}
