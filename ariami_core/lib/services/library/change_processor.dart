import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:ariami_core/models/file_change.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/services/library/duplicate_detector.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';

/// Service for processing file system changes into library updates
class ChangeProcessor {
  final MetadataExtractor _metadataExtractor = MetadataExtractor();
  Set<String> _lastAddedFiles = <String>{};
  Set<String> _lastModifiedFiles = <String>{};
  Set<String> _lastRemovedFiles = <String>{};

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
    final extractedMetadata = <String, SongMetadata>{};

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
    _lastRemovedFiles = removedFiles.toSet();

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
          final metadata =
              await _metadataExtractor.extractMetadataWithDuration(path);
          extractedMetadata[path] = metadata;
          final songId = _generateSongId(metadata.filePath);
          addedSongIds.add(songId);
        } catch (e) {
          print('Error processing added file "$path": $e');
        }
      }
    }

    // Process modifications
    if (modifiedFiles.isNotEmpty) {
      for (final path in modifiedFiles) {
        try {
          final metadata =
              await _metadataExtractor.extractMetadataWithDuration(path);
          extractedMetadata[path] = metadata;
          final songId = _generateSongId(metadata.filePath);
          modifiedSongIds.add(songId);

          // Track prior album membership; post-rebuild index comparison in
          // library_manager_catalog fills in the final affected album IDs.
          final oldAlbumId = filePathToAlbumId[metadata.filePath];
          if (oldAlbumId != null) {
            affectedAlbumIds.add(oldAlbumId);
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
      extractedMetadata: extractedMetadata,
    );
  }

  /// Generates a unique song ID from file path
  String _generateSongId(String filePath) {
    return md5.convert(utf8.encode(filePath)).toString().substring(0, 12);
  }

  /// Applies library updates to rebuild affected portions of the library
  ///
  /// Returns updated LibraryStructure with changes applied
  Future<LibraryStructure> applyUpdates(
      LibraryUpdate update, LibraryStructure currentLibrary,
      {List<FileChange>? sourceChanges}) async {
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
    final removedPaths = <String>{};
    if (sourceChanges != null) {
      for (final change in sourceChanges) {
        switch (change.type) {
          case FileChangeType.added:
          case FileChangeType.modified:
            changedPaths.add(change.path);
            break;
          case FileChangeType.renamed:
            changedPaths.add(change.path);
            if (change.oldPath != null) {
              removedPaths.add(change.oldPath!);
            }
            break;
          case FileChangeType.removed:
            removedPaths.add(change.path);
            break;
        }
      }
    } else {
      changedPaths.addAll(_lastAddedFiles);
      changedPaths.addAll(_lastModifiedFiles);
      removedPaths.addAll(_lastRemovedFiles);
    }

    // Re-extract metadata for changed files
    if (changedPaths.isNotEmpty) {
      for (final path in changedPaths) {
        if (update.extractedMetadata.containsKey(path)) {
          allSongs.add(update.extractedMetadata[path]!);
        } else {
          try {
            final updatedMetadata =
                await _metadataExtractor.extractMetadataWithDuration(path);
            allSongs.add(updatedMetadata);
          } catch (e) {
            print('Error re-extracting metadata for "$path": $e');
          }
        }
      }
    }

    // Carry the full-scan duplicate mapping forward so playlist entries whose
    // folder copy was deduped keep pointing at the surviving song ID. A
    // removed file drops out outright. A rewritten one can no longer be
    // *assumed* to duplicate its old original, so it is revalidated against
    // the freshly extracted metadata rather than discarded: a bulk retag
    // rewrites every file without changing which recording it holds, and
    // dropping those mappings silently strips playlists of every deduped
    // entry until someone runs a full scan.
    final songsByPath = <String, SongMetadata>{
      for (final song in allSongs) song.filePath: song,
    };
    final detector = DuplicateDetector();
    final duplicateToOriginalPath = <String, String>{};
    for (final entry in currentLibrary.duplicateToOriginalPath.entries) {
      if (removedPaths.contains(entry.key) ||
          removedPaths.contains(entry.value)) {
        continue;
      }
      if (changedPaths.contains(entry.key) ||
          changedPaths.contains(entry.value)) {
        final candidate = songsByPath[entry.key];
        final original = songsByPath[entry.value];
        if (candidate == null ||
            original == null ||
            !detector.stillDuplicates(candidate, original)) {
          continue;
        }
      }
      duplicateToOriginalPath[entry.key] = entry.value;
    }

    // A path that is still mapped to an original must not also stand as its
    // own song: re-extracting a changed file adds it back to [allSongs], which
    // would otherwise resurrect the copy that deduplication removed.
    final uniqueSongs = duplicateToOriginalPath.isEmpty
        ? allSongs
        : allSongs
            .where((song) =>
                !duplicateToOriginalPath.containsKey(song.filePath))
            .toList();

    // Rebuild library structure, preserving and updating folder playlists.
    return buildLibraryWithPlaylistsAsync(
      allSongs: uniqueSongs,
      existingPlaylists: currentLibrary.folderPlaylists,
      generateSongId: _generateSongId,
      duplicateToOriginalPath: duplicateToOriginalPath,
    );
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
