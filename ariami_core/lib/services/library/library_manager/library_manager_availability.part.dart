part of '../library_manager.dart';

extension _LibraryManagerAvailabilityPart on LibraryManager {
  void _monitorMusicFolder(String folderPath) {
    _configuredFolderPath = folderPath;
    _availabilityTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(checkMusicAvailability());
    });
  }

  Future<void> _probeMusicFolder(String folderPath) async {
    // Listing checks read access too; exists() alone accepts a dead mount point.
    await Directory(folderPath).list(followLinks: false).take(1).drain<void>();
  }

  Future<void> _checkMusicAvailabilityImpl() async {
    final folderPath = _configuredFolderPath;
    if (folderPath == null ||
        _availabilityTimer == null ||
        _isScanning ||
        _availabilityCheckInFlight) return;
    _availabilityCheckInFlight = true;
    try {
      await _checkStorage(folderPath, checkKnownFiles: true);
      if (_configuredFolderPath != folderPath || _availabilityTimer == null)
        return;
      if (_musicAvailability != MusicAvailability.ready) {
        // A full scan reattaches the watcher, including mounts that appeared
        // after startup and network filesystems that deliver no watch events.
        try {
          await scanMusicFolder(folderPath);
        } catch (_) {
          // The scan records its own failure state and retains the catalogue.
        }
      }
    } catch (error) {
      if (_configuredFolderPath == folderPath && _availabilityTimer != null) {
        _musicAvailability = MusicAvailability.unavailable;
        _stopWatchingFolder();
      }
    } finally {
      _availabilityCheckInFlight = false;
    }
  }

  Future<void> _checkStorage(String folderPath,
      {bool checkKnownFiles = false, Iterable<String>? samplePaths}) async {
    // Retain a pending OS probe after timeout so an unresponsive network mount
    // cannot accumulate a new blocked filesystem operation every 30 seconds.
    if (_storageProbe != null && _storageProbeFolder == folderPath) {
      return _storageProbe!.timeout(const Duration(seconds: 5));
    }
    _storageProbeFolder = folderPath;
    late final Future<void> probe;
    probe = () async {
      await _probeMusicFolder(folderPath);
      if (samplePaths != null ||
          (checkKnownFiles && _musicAvailability == MusicAvailability.ready)) {
        final samples = (samplePaths ?? _songPathById.values).take(3).toList();
        if (samples.isNotEmpty) {
          for (final sample in samples) {
            try {
              final file = await File(sample).open();
              try {
                await file.read(1);
                return;
              } finally {
                await file.close();
              }
            } on FileSystemException {
              // One deleted track must not mark the whole library unavailable.
            }
          }
          throw FileSystemException(
              'Known music files are unavailable', folderPath);
        }
      }
    }()
        .whenComplete(() {
      if (identical(_storageProbe, probe)) _storageProbe = null;
    });
    _storageProbe = probe;
    await probe.timeout(const Duration(seconds: 5));
  }
}
