import 'dart:async';
import 'dart:io';
import 'package:watcher/watcher.dart';
import 'package:bma_core/models/file_change.dart';
import 'package:bma_core/services/library/file_scanner.dart';

/// Service for monitoring music folder for file system changes
class FolderWatcher {
  DirectoryWatcher? _watcher;
  StreamSubscription? _subscription;
  final StreamController<List<FileChange>> _changeController =
      StreamController<List<FileChange>>.broadcast();

  Timer? _debounceTimer;
  final List<FileChange> _pendingChanges = [];
  static const Duration _debounceDelay = Duration(seconds: 2);

  /// Stream of batched file changes
  Stream<List<FileChange>> get changes => _changeController.stream;

  /// Starts watching the specified directory for changes
  ///
  /// Only monitors audio files with supported extensions
  /// Debounces changes by 2 seconds to batch related updates
  void startWatching(String path) {
    if (_subscription != null) {
      stopWatching();
    }

    try {
      _watcher = DirectoryWatcher(path);
      _subscription = _watcher!.events.listen(
        (event) {
          _handleFileSystemEvent(event);
        },
        onError: (error) {
          print('Error watching directory: $error');
        },
      );
      print('Started watching: $path');
    } catch (e) {
      print('Failed to start watching: $e');
    }
  }

  /// Stops watching for file system changes
  void stopWatching() {
    _subscription?.cancel();
    _subscription = null;
    _watcher = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingChanges.clear();
  }

  /// Handles individual file system events
  void _handleFileSystemEvent(WatchEvent event) {
    final path = event.path;

    // Only process audio files
    if (!_isAudioFile(path)) {
      return;
    }

    // Skip temporary files
    if (_isTemporaryFile(path)) {
      return;
    }

    // Convert watcher event to FileChange
    FileChangeType? changeType;
    switch (event.type) {
      case ChangeType.ADD:
        changeType = FileChangeType.added;
        break;
      case ChangeType.REMOVE:
        changeType = FileChangeType.removed;
        break;
      case ChangeType.MODIFY:
        changeType = FileChangeType.modified;
        break;
    }

    if (changeType != null) {
      final fileChange = FileChange(
        path: path,
        type: changeType,
        timestamp: DateTime.now(),
      );

      _addPendingChange(fileChange);
    }
  }

  /// Adds a change to pending list and starts/resets debounce timer
  void _addPendingChange(FileChange change) {
    _pendingChanges.add(change);

    // Reset debounce timer
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      _flushPendingChanges();
    });
  }

  /// Flushes all pending changes to the stream
  void _flushPendingChanges() {
    if (_pendingChanges.isEmpty) {
      return;
    }

    // Create a copy and clear pending
    final changes = List<FileChange>.from(_pendingChanges);
    _pendingChanges.clear();

    // Emit batched changes
    _changeController.add(changes);
  }

  /// Checks if a file is an audio file
  bool _isAudioFile(String path) {
    final extension = path.toLowerCase().substring(path.lastIndexOf('.'));
    return FileScanner.supportedExtensions.contains(extension);
  }

  /// Checks if a file is temporary and should be ignored
  bool _isTemporaryFile(String path) {
    final fileName = path.split(Platform.pathSeparator).last.toLowerCase();
    return fileName.startsWith('.') ||
        fileName.endsWith('.tmp') ||
        fileName.endsWith('.partial') ||
        fileName.endsWith('.download');
  }

  /// Manually triggers a refresh (useful for "Refresh Library" button)
  Future<void> manualRefresh(String path) async {
    // This would trigger a full rescan
    // Implementation depends on how you want to integrate with existing scanner
    print('Manual refresh requested for: $path');
  }

  /// Cleans up resources
  void dispose() {
    stopWatching();
    _changeController.close();
  }
}
