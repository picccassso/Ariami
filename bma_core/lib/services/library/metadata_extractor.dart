import 'dart:io';
import 'package:dart_tags/dart_tags.dart';
import 'package:bma_core/models/song_metadata.dart';
import 'package:bma_core/services/library/mp3_duration_parser.dart';

/// Service for extracting metadata from audio files
class MetadataExtractor {
  final TagProcessor _tagProcessor = TagProcessor();

  /// Extracts metadata from a single audio file
  ///
  /// Returns [SongMetadata] with all available metadata extracted
  /// Falls back to filename parsing if metadata is missing or corrupted
  Future<SongMetadata> extractMetadata(String filePath) async {
    try {
      final file = File(filePath);

      // Get file stats
      final fileStat = await file.stat();
      final fileSize = fileStat.size;
      final modifiedTime = fileStat.modified;

      // Read metadata using dart_tags
      final tags = await _tagProcessor.getTagsFromByteArray(file.readAsBytes());

      // Extract metadata from tags
      String? title;
      String? artist;
      String? album;
      String? albumArtist;
      int? year;
      int? trackNumber;
      int? discNumber;
      String? genre;
      int? duration;
      List<int>? albumArt;

      for (final tag in tags) {
        final tagMap = tag.tags;

        title = title ?? _getTagValue(tagMap, ['title', 'TIT2']);
        artist = artist ?? _getTagValue(tagMap, ['artist', 'TPE1']);
        album = album ?? _getTagValue(tagMap, ['album', 'TALB']);
        albumArtist =
            albumArtist ?? _getTagValue(tagMap, ['albumartist', 'TPE2']);
        genre = genre ?? _getTagValue(tagMap, ['genre', 'TCON']);

        // Extract year
        final yearStr = _getTagValue(tagMap, ['year', 'TYER', 'TDRC']);
        if (yearStr != null && year == null) {
          year = int.tryParse(
            yearStr.split('-').first,
          ); // Handle YYYY or YYYY-MM-DD
        }

        // Extract track number
        final trackStr = _getTagValue(tagMap, ['track', 'TRCK']);
        if (trackStr != null && trackNumber == null) {
          trackNumber = int.tryParse(
            trackStr.split('/').first,
          ); // Handle "3/12" format
        }

        // Extract disc number
        final discStr = _getTagValue(tagMap, ['disc', 'TPOS']);
        if (discStr != null && discNumber == null) {
          discNumber = int.tryParse(
            discStr.split('/').first,
          ); // Handle "1/2" format
        }

        // Skip duration and album art extraction during scan - done lazily on demand
      }

      // Create metadata object
      var songMetadata = SongMetadata(
        filePath: filePath,
        title: title,
        artist: artist,
        albumArtist: albumArtist,
        album: album,
        year: year,
        trackNumber: trackNumber,
        discNumber: discNumber,
        genre: genre,
        duration: duration,
        bitrate: null, // dart_tags doesn't provide bitrate easily
        comment: null,
        albumArt: albumArt,
        fileSize: fileSize,
        modifiedTime: modifiedTime,
      );

      // If title is missing, try to parse from filename
      if (songMetadata.title == null || songMetadata.title!.isEmpty) {
        songMetadata = _parseFromFilename(songMetadata);
      }

      return songMetadata;
    } catch (e) {
      // If metadata extraction fails, create metadata from filename only
      final file = File(filePath);
      final fileStat = await file.stat();

      return _parseFromFilename(
        SongMetadata(
          filePath: filePath,
          fileSize: fileStat.size,
          modifiedTime: fileStat.modified,
        ),
      );
    }
  }

  /// Helper to get tag value by trying multiple key names
  dynamic _getTagValue(Map<String, dynamic> tagMap, List<String> keys) {
    for (final key in keys) {
      if (tagMap.containsKey(key)) {
        return tagMap[key];
      }
    }
    return null;
  }

  /// Extracts metadata from multiple files in batches
  ///
  /// Yields batches of [SongMetadata] as they are processed
  /// Batch size is configurable (default: 50)
  Stream<List<SongMetadata>> extractMetadataBatch(
    List<String> filePaths, {
    int batchSize = 50,
  }) async* {
    final batches = <List<String>>[];

    // Split into batches
    for (var i = 0; i < filePaths.length; i += batchSize) {
      final end = (i + batchSize < filePaths.length)
          ? i + batchSize
          : filePaths.length;
      batches.add(filePaths.sublist(i, end));
    }

    // Process each batch
    for (final batch in batches) {
      final metadataList = <SongMetadata>[];

      // Process files sequentially to handle errors gracefully
      for (final path in batch) {
        try {
          final metadata = await extractMetadata(path);
          metadataList.add(metadata);
        } catch (e) {
          // Skip files that can't be processed
          print('Warning: Failed to extract metadata from $path: $e');
        }
      }

      if (metadataList.isNotEmpty) {
        yield metadataList;
      }
    }
  }

  /// Parses song information from filename when metadata is missing
  ///
  /// Supports common patterns:
  /// - "01 - Artist - Song Title.mp3"
  /// - "Artist - Album - 01 - Title.mp3"
  /// - "01_Song_Title.mp3"
  /// - "Song Title.mp3"
  SongMetadata _parseFromFilename(SongMetadata metadata) {
    final fileName = _getFileNameWithoutExtension(metadata.filePath);

    // Try pattern: "01 - Artist - Song Title"
    var pattern1 = RegExp(r'^(\d+)\s*-\s*(.+?)\s*-\s*(.+)$');
    var match = pattern1.firstMatch(fileName);
    if (match != null) {
      return metadata.copyWith(
        trackNumber: int.tryParse(match.group(1)!),
        artist: match.group(2)!.trim(),
        title: match.group(3)!.trim(),
      );
    }

    // Try pattern: "Artist - Album - 01 - Title"
    var pattern2 = RegExp(r'^(.+?)\s*-\s*(.+?)\s*-\s*(\d+)\s*-\s*(.+)$');
    match = pattern2.firstMatch(fileName);
    if (match != null) {
      return metadata.copyWith(
        artist: match.group(1)!.trim(),
        album: match.group(2)!.trim(),
        trackNumber: int.tryParse(match.group(3)!),
        title: match.group(4)!.trim(),
      );
    }

    // Try pattern: "01_Song_Title" or "01 Song Title"
    var pattern3 = RegExp(r'^(\d+)[_\s]+(.+)$');
    match = pattern3.firstMatch(fileName);
    if (match != null) {
      return metadata.copyWith(
        trackNumber: int.tryParse(match.group(1)!),
        title: match.group(2)!.trim().replaceAll('_', ' '),
      );
    }

    // Default: use filename as title
    return metadata.copyWith(title: fileName.replaceAll('_', ' '));
  }

  /// Gets the filename without extension
  String _getFileNameWithoutExtension(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) {
      return fileName;
    }
    return fileName.substring(0, lastDot);
  }

  /// Extract audio duration from file
  ///
  /// Currently supports MP3 files using pure Dart parsing.
  /// Other formats will return null.
  Future<int?> extractDuration(String filePath) async {
    try {
      final extension = filePath.split('.').last.toLowerCase();
      
      if (extension == 'mp3') {
        final parser = Mp3DurationParser();
        return await parser.getDuration(filePath);
      }
      
      // Other formats not yet supported
      return null;
    } catch (e) {
      // Silently fail - duration is optional
      return null;
    }
  }

  /// Cleanup method - no longer needed but kept for API compatibility
  Future<void> dispose() async {
    // No resources to clean up - duration extraction now uses fresh players
  }

  /// Extracts album artwork from a single audio file (lazy extraction)
  ///
  /// This is called on-demand when artwork is requested, not during scan.
  /// Returns the artwork bytes or null if no artwork found.
  Future<List<int>?> extractArtwork(String filePath) async {
    try {
      final file = File(filePath);
      final tags = await _tagProcessor.getTagsFromByteArray(file.readAsBytes());

      for (final tag in tags) {
        final tagMap = tag.tags;
        final picture = _getTagValue(tagMap, ['picture', 'APIC', 'PIC', 'METADATA_BLOCK_PICTURE']);

        if (picture != null) {
          if (picture is List) {
            return List<int>.from(picture);
          } else if (picture is Map) {
            final pictureKeys = picture.keys.toList();
            if (pictureKeys.isNotEmpty) {
              final imageData = picture[pictureKeys.first];
              if (imageData is List) {
                return List<int>.from(imageData);
              } else {
                // It's an AttachedPicture object - get the imageData property
                try {
                  final dynamic attachedPicture = imageData;
                  final pictureData = attachedPicture.imageData;
                  if (pictureData is List) {
                    return List<int>.from(pictureData);
                  }
                } catch (e) {
                  // Failed to extract from AttachedPicture
                }
              }
            }
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
