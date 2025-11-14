/// Models for file system change detection
library;

/// Types of file system changes
enum FileChangeType {
  added,
  removed,
  modified,
  renamed,
}

/// Represents a single file system change event
class FileChange {
  final String path;
  final FileChangeType type;
  final DateTime timestamp;
  final String? oldPath; // For renamed files

  const FileChange({
    required this.path,
    required this.type,
    required this.timestamp,
    this.oldPath,
  });

  @override
  String toString() {
    return 'FileChange(type: $type, path: $path, timestamp: $timestamp)';
  }
}

/// Represents a batch of library updates after processing changes
class LibraryUpdate {
  final Set<String> addedSongIds;
  final Set<String> removedSongIds;
  final Set<String> modifiedSongIds;
  final Set<String> affectedAlbumIds;
  final DateTime timestamp;

  const LibraryUpdate({
    required this.addedSongIds,
    required this.removedSongIds,
    required this.modifiedSongIds,
    required this.affectedAlbumIds,
    required this.timestamp,
  });

  bool get isEmpty =>
      addedSongIds.isEmpty &&
      removedSongIds.isEmpty &&
      modifiedSongIds.isEmpty &&
      affectedAlbumIds.isEmpty;

  @override
  String toString() {
    return 'LibraryUpdate(added: ${addedSongIds.length}, '
        'removed: ${removedSongIds.length}, '
        'modified: ${modifiedSongIds.length}, '
        'affectedAlbums: ${affectedAlbumIds.length})';
  }
}
