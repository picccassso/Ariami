import 'dart:async';
import 'dart:io';
import 'package:watcher/watcher.dart';
import 'package:ariami_core/models/file_change.dart';
import 'package:ariami_core/services/library/file_scanner.dart';

class FolderWatcher {
  DirectoryWatcher? _watcher;
  StreamSubscription? _subscription;
  final StreamController<List<FileChange>> _changeController =
      StreamController<List<FileChange>>.broadcast();

  Timer? _debounceTimer;
  final List<FileChange> _pendingChanges = [];
  static const Duration _debounceDelay = Duration(seconds: 2);

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

  void stopWatching() {
    _subscription?.cancel();
    _subscription = null;
    _watcher = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingChanges.clear();
  }

  void _handleFileSystemEvent(WatchEvent event) {
    final path = event.path;

    if (!_isAudioFile(path)) {
      return;
    }

    if (_isTemporaryFile(path)) {
      return;
    }

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

  void _addPendingChange(FileChange change) {
    _pendingChanges.add(change);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      _flushPendingChanges();
    });
  }

  void _flushPendingChanges() {
    if (_pendingChanges.isEmpty) {
      return;
    }

    final changes = List<FileChange>.from(_pendingChanges);
    _pendingChanges.clear();

    _changeController.add(changes);
  }

  bool _isAudioFile(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == path.length - 1) {
      return false;
    }
    final extension = path.toLowerCase().substring(dotIndex);
    return FileScanner.supportedExtensions.contains(extension);
  }

  bool _isTemporaryFile(String path) {
    final fileName = path.split(Platform.pathSeparator).last.toLowerCase();
    return fileName.startsWith('.') ||
        fileName.endsWith('.tmp') ||
        fileName.endsWith('.partial') ||
        fileName.endsWith('.download');
  }

  void dispose() {
    stopWatching();
    _changeController.close();
  }
}
