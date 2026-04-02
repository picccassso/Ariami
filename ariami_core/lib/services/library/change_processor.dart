import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:ariami_core/models/file_change.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/services/library/album_grouping.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/album_builder.dart';

/// Service for processing file system changes into library updates
class ChangeProcessor {
  final MetadataExtractor _metadataExtractor = MetadataExtractor();
  final AlbumBuilder _albumBuilder = AlbumBuilder();
  Set<String> _lastAddedFiles = <String>{};
  Set<String> _lastModifiedFiles = <String>{};

  /// Processes a batch of file changes and generates library updates
  ///
  /// Takes raw file system changes and converts them into structured
  /// library updates with song IDs and affected album IDs
  Future<LibraryUpdate> processChanges(
    List<FileChange> changes,
    LibraryStructure currentLibrary,
  ) async {
    final addedSongIds = <String>{};
    final removedSongIds = <String>{};
    final modifiedSongIds = <String>{};
    final affectedAlbumIds = <String>{};

    // Build reverse index for O(1) lookups (filePath -> albumId)
    // This replaces O(A×S) linear search with O(1) hash map lookup
    final filePathToAlbumId = <String, String>{};
    for (final album in currentLibrary.albums.values) {
      for (final song in album.songs) {
        filePathToAlbumId[song.filePath] = album.id;
      }
    }

    // Group changes by type
    final addedFiles = <String>{};
    final removedFiles = <String>[];
    final modifiedFiles = <String>{};

    for (final change in changes) {
      switch (change.type) {
        case FileChangeType.added:
          addedFiles.add(change.path);
          break;
        case FileChangeType.removed:
          removedFiles.add(change.path);
          break;
        case FileChangeType.modified:
          modifiedFiles.add(change.path);
          break;
        case FileChangeType.renamed:
          // Treat as remove old + add new
          if (change.oldPath != null) {
            removedFiles.add(change.oldPath!);
          }
          addedFiles.add(change.path);
          break;
      }
    }

    _lastAddedFiles = addedFiles;
    _lastModifiedFiles = modifiedFiles;

    // Process removals
    for (final path in removedFiles) {
      final songId = _generateSongId(path);
      removedSongIds.add(songId);

      // Find which album this song belonged to (O(1) lookup)
      final albumId = filePathToAlbumId[path];
      if (albumId != null) {
        affectedAlbumIds.add(albumId);
      }
    }

    // Process additions
    if (addedFiles.isNotEmpty) {
      for (final path in addedFiles) {
        try {
          final metadata = await _metadataExtractor.extractMetadata(path);
          final songId = _generateSongId(metadata.filePath);
          addedSongIds.add(songId);

          // Determine which album this will affect
          final albumKey = albumGroupingKey(metadata);
          if (albumKey != null) {
            final albumId = _generateAlbumId(albumKey);
            affectedAlbumIds.add(albumId);
          }
        } catch (e) {
          print('Error processing added file "$path": $e');
        }
      }
    }

    // Process modifications
    if (modifiedFiles.isNotEmpty) {
      for (final path in modifiedFiles) {
        try {
          final metadata = await _metadataExtractor.extractMetadata(path);
          final songId = _generateSongId(metadata.filePath);
          modifiedSongIds.add(songId);

          // Find affected albums (could be old and new if metadata changed)
          // O(1) lookup using reverse index
          final oldAlbumId = filePathToAlbumId[metadata.filePath];
          if (oldAlbumId != null) {
            affectedAlbumIds.add(oldAlbumId);
          }

          final albumKey = albumGroupingKey(metadata);
          if (albumKey != null) {
            final newAlbumId = _generateAlbumId(albumKey);
            affectedAlbumIds.add(newAlbumId);
          }
        } catch (e) {
          print('Error processing modified file "$path": $e');
        }
      }
    }

    return LibraryUpdate(
      addedSongIds: addedSongIds,
      removedSongIds: removedSongIds,
      modifiedSongIds: modifiedSongIds,
      affectedAlbumIds: affectedAlbumIds,
      timestamp: DateTime.now(),
    );
  }

  /// Generates a unique song ID from file path
  String _generateSongId(String filePath) {
    return md5.convert(utf8.encode(filePath)).toString().substring(0, 12);
  }

  /// Generates a unique album ID from album key
  String _generateAlbumId(String albumKey) {
    return md5.convert(utf8.encode(albumKey)).toString();
  }

  /// Applies library updates to rebuild affected portions of the library
  ///
  /// Returns updated LibraryStructure with changes applied
  Future<LibraryStructure> applyUpdates(
    LibraryUpdate update,
    LibraryStructure currentLibrary,
    {List<FileChange>? sourceChanges}
  ) async {
    // Collect all songs that need to be in the updated library
    final allSongs = <SongMetadata>[];

    // Keep songs that weren't removed or modified
    for (final album in currentLibrary.albums.values) {
      for (final song in album.songs) {
        final songId = _generateSongId(song.filePath);
        if (!update.removedSongIds.contains(songId) &&
            !update.modifiedSongIds.contains(songId)) {
          allSongs.add(song);
        }
      }
    }

    for (final song in currentLibrary.standaloneSongs) {
      final songId = _generateSongId(song.filePath);
      if (!update.removedSongIds.contains(songId) &&
          !update.modifiedSongIds.contains(songId)) {
        allSongs.add(song);
      }
    }

    // Add new and modified songs (re-extract metadata from changed paths)
    final changedPaths = <String>{};
    if (sourceChanges != null) {
      for (final change in sourceChanges) {
        switch (change.type) {
          case FileChangeType.added:
          case FileChangeType.modified:
            changedPaths.add(change.path);
            break;
          case FileChangeType.renamed:
            changedPaths.add(change.path);
            break;
          case FileChangeType.removed:
            break;
        }
      }
    } else {
      changedPaths.addAll(_lastAddedFiles);
      changedPaths.addAll(_lastModifiedFiles);
    }

    // Re-extract metadata for changed files
    if (changedPaths.isNotEmpty) {
      for (final path in changedPaths) {
        try {
          final updatedMetadata = await _metadataExtractor.extractMetadata(path);
          allSongs.add(updatedMetadata);
        } catch (e) {
          print('Error re-extracting metadata for "$path": $e');
        }
      }
    }

    // Rebuild library structure
    return _albumBuilder.buildLibrary(allSongs);
  }

  /// Checks if a file still exists and hasn't been modified
  Future<bool> isFileUnchanged(String path, DateTime lastModified) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return false;
      }

      final stat = await file.stat();
      return stat.modified == lastModified;
    } catch (e) {
      return false;
    }
  }
}
