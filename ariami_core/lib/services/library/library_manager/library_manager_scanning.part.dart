part of '../library_manager.dart';

extension _LibraryManagerScanningPart on LibraryManager {
  void _markDurationsDirty() {
    _durationsReady = false;
    _durationWarmupRunning = false;
    _durationCache.clear();
  }

  void _startWatchingFolder(String folderPath) {
    if (_watchedFolderPath == folderPath && _folderChangeSubscription != null) {
      return;
    }

    _stopWatchingFolder();
    _folderChangeSubscription = _folderWatcher.changes.listen(
      (changes) {
        _folderChangePipeline = _folderChangePipeline
            .then((_) => _handleBatchedFileChanges(changes))
            .catchError((error, stackTrace) {
          print(
              '[LibraryManager] WARNING: Folder change pipeline error: $error');
          print('[LibraryManager] Folder change stack trace: $stackTrace');
        });
      },
      onError: (error) {
        print('[LibraryManager] ERROR: Folder watcher stream error: $error');
      },
    );
    _folderWatcher.startWatching(folderPath);
    _watchedFolderPath = folderPath;
  }

  void _stopWatchingFolder() {
    _folderChangeSubscription?.cancel();
    _folderChangeSubscription = null;
    _folderWatcher.stopWatching();
    _watchedFolderPath = null;
  }

  Future<void> _handleBatchedFileChanges(List<FileChange> changes) async {
    final currentLibrary = _library;
    if (currentLibrary == null || changes.isEmpty) {
      return;
    }

    if (_isScanning) {
      return;
    }

    try {
      final update =
          await _changeProcessor.processChanges(changes, currentLibrary);
      if (update.isEmpty) {
        return;
      }

      final updatedLibrary = await _changeProcessor.applyUpdates(
        update,
        currentLibrary,
        sourceChanges: changes,
      );
      _library = updatedLibrary;
      _lastScanTime = DateTime.now();
      _durationsReady = false;
      _durationWarmupRunning = false;

      await this._writeCatalogBatchForChanges(
        update: update,
        previousLibrary: currentLibrary,
        updatedLibrary: updatedLibrary,
      );

      print('[LibraryManager] Applied file-change batch '
          '(added: ${update.addedSongIds.length}, '
          'removed: ${update.removedSongIds.length}, '
          'modified: ${update.modifiedSongIds.length}, '
          'affectedAlbums: ${update.affectedAlbumIds.length}, '
          'latestToken: $_latestCatalogToken)');

      _notifyScanComplete();
      unawaited(this._startDurationWarmup());
    } catch (e, stackTrace) {
      print('[LibraryManager] ERROR applying file-change batch: $e');
      print('[LibraryManager] File-change stack trace: $stackTrace');
    }
  }

  Future<void> _scanMusicFolderImpl(String folderPath) async {
    if (_isScanning) {
      print('[LibraryManager] Scan already in progress');
      return;
    }

    _isScanning = true;
    print(
        '[LibraryManager] Starting library scan (background isolate): $folderPath');

    try {
      // Load existing metadata cache if available
      Map<String, Map<String, dynamic>>? cacheData;
      if (_metadataCache != null) {
        await _metadataCache!.load();
        cacheData = _metadataCache!.exportForIsolate();
        print('[LibraryManager] Loaded ${cacheData.length} cached entries');
      }

      // Run the scan in a background isolate
      final result = await LibraryScannerIsolate.scan(
        folderPath,
        onProgress: (progress) {
          // Log progress updates from the isolate
          print('[LibraryManager] [${progress.stage}] ${progress.message} '
              '(${progress.percentage.toStringAsFixed(1)}%)');
        },
        cacheData: cacheData,
      );

      if (result.library != null) {
        _library = result.library;
        _lastScanTime = DateTime.now();
        _markDurationsDirty();

        // Save updated cache
        if (_metadataCache != null && result.updatedCache != null) {
          _metadataCache!.importFromIsolate(result.updatedCache!);
          await _metadataCache!.save();
          print(
              '[LibraryManager] Cache stats: ${result.cacheHits} hits, ${result.cacheMisses} extractions');
        }

        print('[LibraryManager] Library scan complete!');
        print('[LibraryManager] Albums: ${_library!.totalAlbums}');
        print(
            '[LibraryManager] Standalone songs: ${_library!.standaloneSongs.length}');
        print('[LibraryManager] Folder playlists: ${_library!.totalPlaylists}');
        print('[LibraryManager] Total songs: ${_library!.totalSongs}');

        // Persist deterministic catalog rows + change log for v2 sync.
        await this._writeCatalogSnapshot();

        // Watch for incremental filesystem changes after scan.
        _startWatchingFolder(folderPath);

        // Notify listeners that scan is complete
        _notifyScanComplete();

        // Warm up durations asynchronously (non-blocking)
        unawaited(this._startDurationWarmup());
      } else {
        print(
            '[LibraryManager] Scan returned null - possible error in isolate');
      }
    } catch (e, stackTrace) {
      print('[LibraryManager] ERROR during scan: $e');
      print('[LibraryManager] Stack trace: $stackTrace');
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  void _clearImpl() {
    _stopWatchingFolder();
    _library = null;
    _lastScanTime = null;
    _artworkCache.clear();
    _durationCache.clear();
    _songArtworkCache.clear();
    _durationsReady = false;
    _durationWarmupRunning = false;
    print('[LibraryManager] Library cleared');
  }
}
