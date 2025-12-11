import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:bma_core/models/song_metadata.dart';

/// Represents a group of duplicate songs
class DuplicateGroup {
  /// The original/preferred file
  final SongMetadata original;

  /// List of duplicate files
  final List<SongMetadata> duplicates;

  /// The type of match that identified these as duplicates
  final DuplicateMatchType matchType;

  /// Confidence level (0.0 to 1.0)
  final double confidence;

  const DuplicateGroup({
    required this.original,
    required this.duplicates,
    required this.matchType,
    required this.confidence,
  });

  /// Total number of files in this duplicate group
  int get totalFiles => duplicates.length + 1;
}

/// Types of duplicate matches
enum DuplicateMatchType {
  exactHash,      // Exact file hash match
  fileSize,       // Same file size
  metadata,       // Matching metadata (artist, title, album, duration)
}

/// Service for detecting duplicate songs in the library
class DuplicateDetector {
  /// Detects all duplicates in a list of songs
  ///
  /// Returns a list of duplicate groups found
  Future<List<DuplicateGroup>> detectDuplicates(
    List<SongMetadata> songs, {
    bool useHashMatching = true,
    bool useMetadataMatching = true,
  }) async {
    final duplicateGroups = <DuplicateGroup>[];

    // Level 1: Exact hash matching
    if (useHashMatching) {
      final hashGroups = await _findHashDuplicates(songs);
      duplicateGroups.addAll(hashGroups);
    }

    // Level 2: Metadata matching (for remaining songs)
    if (useMetadataMatching) {
      final processedPaths = _getProcessedPaths(duplicateGroups);
      final remainingSongs = songs
          .where((s) => !processedPaths.contains(s.filePath))
          .toList();

      final metadataGroups = _findMetadataDuplicates(remainingSongs);
      duplicateGroups.addAll(metadataGroups);
    }

    return duplicateGroups;
  }

  /// Finds duplicates by comparing file hashes
  Future<List<DuplicateGroup>> _findHashDuplicates(
    List<SongMetadata> songs,
  ) async {
    final hashMap = <String, List<SongMetadata>>{};

    // Group songs by file hash
    for (final song in songs) {
      try {
        final hash = await _calculateFileHash(song.filePath);
        hashMap.putIfAbsent(hash, () => []);
        hashMap[hash]!.add(song);
      } catch (e) {
        // Skip files that can't be hashed
        continue;
      }
    }

    // Create duplicate groups for files with same hash
    final groups = <DuplicateGroup>[];
    for (final entry in hashMap.entries) {
      if (entry.value.length > 1) {
        final sorted = _sortByQuality(entry.value);
        groups.add(DuplicateGroup(
          original: sorted.first,
          duplicates: sorted.sublist(1),
          matchType: DuplicateMatchType.exactHash,
          confidence: 1.0, // Exact match
        ));
      }
    }

    return groups;
  }

  /// Finds duplicates by comparing metadata
  List<DuplicateGroup> _findMetadataDuplicates(List<SongMetadata> songs) {
    final groups = <DuplicateGroup>[];
    final processed = <String>{};

    for (var i = 0; i < songs.length; i++) {
      if (processed.contains(songs[i].filePath)) continue;

      final matches = <SongMetadata>[];

      for (var j = i + 1; j < songs.length; j++) {
        if (processed.contains(songs[j].filePath)) continue;

        if (_isMetadataMatch(songs[i], songs[j])) {
          matches.add(songs[j]);
          processed.add(songs[j].filePath);
        }
      }

      if (matches.isNotEmpty) {
        final allMatches = [songs[i], ...matches];
        final sorted = _sortByQuality(allMatches);

        groups.add(DuplicateGroup(
          original: sorted.first,
          duplicates: sorted.sublist(1),
          matchType: DuplicateMatchType.metadata,
          confidence: 0.85, // High confidence but not exact
        ));

        processed.add(songs[i].filePath);
      }
    }

    return groups;
  }

  /// Checks if two songs match by metadata
  bool _isMetadataMatch(SongMetadata a, SongMetadata b) {
    // Both must have title
    if (a.title == null || b.title == null) return false;

    // Compare titles (case insensitive, normalized)
    final titleA = _normalizeString(a.title!);
    final titleB = _normalizeString(b.title!);
    if (titleA != titleB) return false;

    // Compare artists (case insensitive, normalized)
    final artistA = _normalizeString(a.artist ?? '');
    final artistB = _normalizeString(b.artist ?? '');
    if (artistA != artistB) return false;

    // Compare albums (optional, but if both have it, should match)
    if (a.album != null && b.album != null) {
      final albumA = _normalizeString(a.album!);
      final albumB = _normalizeString(b.album!);
      if (albumA != albumB) return false;
    }

    // Compare duration (±2 seconds tolerance)
    if (a.duration != null && b.duration != null) {
      final durationDiff = (a.duration! - b.duration!).abs();
      if (durationDiff > 2) return false;
    }

    return true;
  }

  /// Normalizes a string for comparison
  String _normalizeString(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove special characters
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  /// Sorts songs by quality (best first)
  ///
  /// Priority:
  /// 1. Lossless formats (.flac, .wav, .aiff)
  /// 2. Complete metadata
  /// 3. Larger file size (usually higher quality)
  List<SongMetadata> _sortByQuality(List<SongMetadata> songs) {
    final sorted = List<SongMetadata>.from(songs);

    sorted.sort((a, b) {
      // Check for lossless format
      final aLossless = _isLosslessFormat(a.filePath);
      final bLossless = _isLosslessFormat(b.filePath);
      if (aLossless && !bLossless) return -1;
      if (!aLossless && bLossless) return 1;

      // Check metadata completeness
      final aComplete = a.isComplete ? 1 : 0;
      final bComplete = b.isComplete ? 1 : 0;
      if (aComplete != bComplete) return bComplete.compareTo(aComplete);

      // Compare file size (larger is usually better quality)
      final aSize = a.fileSize ?? 0;
      final bSize = b.fileSize ?? 0;
      return bSize.compareTo(aSize);
    });

    return sorted;
  }

  /// Checks if a file is a lossless format
  bool _isLosslessFormat(String filePath) {
    final ext = filePath.substring(filePath.lastIndexOf('.')).toLowerCase();
    return ['.flac', '.wav', '.aiff', '.alac'].contains(ext);
  }

  /// Calculates MD5 hash of a file
  Future<String> _calculateFileHash(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// Gets all file paths that have been processed in duplicate groups
  Set<String> _getProcessedPaths(List<DuplicateGroup> groups) {
    final paths = <String>{};
    for (final group in groups) {
      paths.add(group.original.filePath);
      for (final dup in group.duplicates) {
        paths.add(dup.filePath);
      }
    }
    return paths;
  }

  /// Filters a list of songs to exclude duplicates
  ///
  /// Returns only the "original" (best quality) version of each song
  List<SongMetadata> filterDuplicates(
    List<SongMetadata> songs,
    List<DuplicateGroup> duplicateGroups,
  ) {
    final duplicatePaths = <String>{};

    // Collect all duplicate paths
    for (final group in duplicateGroups) {
      for (final dup in group.duplicates) {
        duplicatePaths.add(dup.filePath);
      }
    }

    // Return songs that are not duplicates
    return songs
        .where((song) => !duplicatePaths.contains(song.filePath))
        .toList();
  }
}
