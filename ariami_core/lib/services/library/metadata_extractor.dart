import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:dart_tags/dart_tags.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/mp3_duration_parser.dart';

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

      // Read metadata using optimized tag reading (reads only tag sections, not entire file)
      final tags = await _readTagsOptimized(file, fileSize);

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

        title = title ?? _fixEncoding(_getTagValue(tagMap, ['title', 'TIT2']));
        artist =
            artist ?? _fixEncoding(_getTagValue(tagMap, ['artist', 'TPE1']));
        album = album ?? _fixEncoding(_getTagValue(tagMap, ['album', 'TALB']));
        albumArtist = albumArtist ??
            _fixEncoding(_getTagValue(tagMap, ['albumartist', 'TPE2']));
        genre = genre ?? _fixEncoding(_getTagValue(tagMap, ['genre', 'TCON']));

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

  /// Reads only the tag sections of an audio file instead of the entire file
  ///
  /// For MP3: Reads ID3v2 header + tag data + ID3v1 tail (if present)
  /// For other formats: Reads first 64KB (usually contains all metadata)
  /// Falls back to full file read if optimized parsing fails.
  Future<List<Tag>> _readTagsOptimized(File file, int fileSize) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        // Read first 10 bytes to check for ID3v2 header
        final header = await raf.read(10);
        if (header.length < 10) {
          // File too small, read whole thing
          await raf.close();
          return await _tagProcessor.getTagsFromByteArray(file.readAsBytes());
        }

        int tagSize = 0;
        bool hasId3v2 = false;

        // Check for ID3v2 header: "ID3" signature
        if (header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33) {
          hasId3v2 = true;
          // Calculate tag size using syncsafe integer (7 bits per byte)
          tagSize = 10 + (((header[6] & 0x7F) << 21) |
                         ((header[7] & 0x7F) << 14) |
                         ((header[8] & 0x7F) << 7) |
                         (header[9] & 0x7F));
        }

        // Read tag section (or first 64KB for non-ID3v2 formats like M4A/FLAC)
        await raf.setPosition(0);
        final bytesToRead = hasId3v2 ? tagSize : min(65536, fileSize);
        final tagBytes = await raf.read(bytesToRead);

        // Check for ID3v1 at end of file (last 128 bytes, starts with "TAG")
        Uint8List? id3v1Bytes;
        if (fileSize > 128) {
          await raf.setPosition(fileSize - 128);
          final tail = await raf.read(128);
          if (tail.length == 128 &&
              tail[0] == 0x54 && tail[1] == 0x41 && tail[2] == 0x47) { // "TAG"
            id3v1Bytes = tail;
          }
        }

        await raf.close();

        // Combine bytes: tag section + ID3v1 (if present)
        final Uint8List allBytes;
        if (id3v1Bytes != null) {
          allBytes = Uint8List(tagBytes.length + id3v1Bytes.length);
          allBytes.setAll(0, tagBytes);
          allBytes.setAll(tagBytes.length, id3v1Bytes);
        } else {
          allBytes = tagBytes;
        }

        // Parse tags from the combined bytes
        return await _tagProcessor.getTagsFromByteArray(Future.value(allBytes));
      } catch (e) {
        await raf.close();
        rethrow;
      }
    } catch (e) {
      // Fallback: read entire file (original behavior)
      return await _tagProcessor.getTagsFromByteArray(file.readAsBytes());
    }
  }

  /// Fixes mojibake (UTF-8 bytes misread as Latin-1)
  /// Detects patterns like "Ã¡" (should be "á") and repairs them
  /// This happens when ID3 tags claim Latin-1 encoding but contain UTF-8 bytes
  ///
  /// Handles various character sets:
  /// - Western European (Spanish, French, etc.): Ã, Â patterns
  /// - Korean (Hangul): ì, í, î patterns (3-byte UTF-8)
  /// - Japanese/Chinese (CJK): Similar multi-byte patterns
  String? _fixEncoding(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    if (str.isEmpty) return str;

    try {
      // Always attempt to fix encoding by re-encoding as Latin-1 and decoding as UTF-8
      // This will fix mojibake for all character sets (Western, Korean, Japanese, Chinese, etc.)
      final latin1Bytes = latin1.encode(str);
      final fixedStr = utf8.decode(latin1Bytes, allowMalformed: true);

      // Only use the fixed version if it's different and appears to be valid
      // Check if the fix actually changed something and produced valid UTF-8
      if (fixedStr != str && fixedStr.isNotEmpty) {
        // Verify the fixed string doesn't contain replacement characters
        // which would indicate invalid UTF-8
        if (!fixedStr.contains('�')) {
          return fixedStr;
        }
      }

      return str;
    } catch (e) {
      // If conversion fails, return original
      return str;
    }
  }

  /// Extracts metadata and duration from a single audio file in one call
  /// 
  /// This is more efficient than calling extractMetadata and extractDuration
  /// separately as it reduces the number of method calls and allows for
  /// potential future optimizations like shared file reads.
  Future<SongMetadata> extractMetadataWithDuration(String filePath) async {
    var metadata = await extractMetadata(filePath);
    final duration = await extractDuration(filePath);
    if (duration != null) {
      metadata = metadata.copyWith(duration: duration);
    }
    return metadata;
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

  /// Cache for ffprobe availability check
  bool? _ffprobeAvailable;

  /// Check if ffprobe is available on the system
  Future<bool> _isFFprobeAvailable() async {
    if (_ffprobeAvailable != null) return _ffprobeAvailable!;

    try {
      final result = await Process.run('ffprobe', ['-version']);
      _ffprobeAvailable = result.exitCode == 0;
    } catch (e) {
      _ffprobeAvailable = false;
    }

    return _ffprobeAvailable!;
  }

  /// Extract audio duration from file
  ///
  /// Uses ffprobe for all formats (most reliable), falls back to
  /// pure Dart MP3 parser if ffprobe is unavailable.
  Future<int?> extractDuration(String filePath) async {
    // Try ffprobe first (works for all formats)
    if (await _isFFprobeAvailable()) {
      try {
        final result = await Process.run('ffprobe', [
          '-v', 'quiet',
          '-show_entries', 'format=duration',
          '-of', 'json',
          filePath,
        ]).timeout(const Duration(seconds: 5));

        if (result.exitCode == 0) {
          final json = jsonDecode(result.stdout as String);
          final format = json['format'] as Map<String, dynamic>?;
          if (format != null) {
            final durationStr = format['duration']?.toString();
            if (durationStr != null) {
              final durationSeconds = double.tryParse(durationStr);
              if (durationSeconds != null) {
                return durationSeconds.round();
              }
            }
          }
        }
      } catch (e) {
        // ffprobe failed, try fallback
      }
    }

    // Fallback to pure Dart MP3 parser for MP3 files
    try {
      final extension = filePath.split('.').last.toLowerCase();

      if (extension == 'mp3') {
        final parser = Mp3DurationParser();
        return await parser.getDuration(filePath);
      }

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
