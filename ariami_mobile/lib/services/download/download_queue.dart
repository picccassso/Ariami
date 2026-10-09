import 'dart:async';
import '../../models/download_task.dart';

/// Manages the download queue with priority and order
class DownloadQueue {
  final List<DownloadTask> _queue = [];
  final StreamController<List<DownloadTask>> _queueController =
      StreamController<List<DownloadTask>>.broadcast();
  int _batchDepth = 0;
  bool _batchDirty = false;

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

  /// Remove tasks matching a predicate
  void dequeueWhere(bool Function(DownloadTask) predicate) {
    _queue.removeWhere(predicate);
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

  /// Replace a task whose identity changed, such as a path-derived song ID.
  bool replaceTask(String existingTaskId, DownloadTask replacement) {
    final index = _queue.indexWhere((task) => task.id == existingTaskId);
    if (index < 0) return false;
    if (_queue.any(
        (task) => task.id == replacement.id && task.id != existingTaskId)) {
      return false;
    }

    _queue[index] = replacement;
    _notifyListeners();
    return true;
  }

  /// Clear entire queue
  void clear() {
    _queue.clear();
    _notifyListeners();
  }

  /// Begin suppressing intermediate stream notifications.
  void beginBatch() {
    _batchDepth++;
  }

  /// End a batch and emit one consolidated queue event if needed.
  void endBatch() {
    if (_batchDepth == 0) return;
    _batchDepth--;
    if (_batchDepth == 0 && _batchDirty) {
      _batchDirty = false;
      _queueController.add(List.unmodifiable(_queue));
    }
  }

  /// Notify listeners of queue changes
  void _notifyListeners() {
    if (_batchDepth > 0) {
      _batchDirty = true;
      return;
    }
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

  /// Check if any downloads are active
  bool get hasActiveDownloads => downloading > 0 || paused > 0;
}
