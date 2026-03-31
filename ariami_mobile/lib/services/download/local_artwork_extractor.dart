import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:dart_tags/dart_tags.dart';

/// Extracts embedded album art from local audio files (mirrors
/// [ariami_core] `MetadataExtractor.extractArtwork` without pulling in core).
class LocalArtworkExtractor {
  LocalArtworkExtractor._();

  static final TagProcessor _tagProcessor = TagProcessor();

  /// Returns embedded picture bytes, or null if none found.
  static Future<List<int>?> extractArtwork(String filePath) async {
    try {
      final file = File(filePath);
      final fileStat = await file.stat();
      final fileSize = fileStat.size;
      final extension = filePath.split('.').last.toLowerCase();

      const optimizedFormats = {'mp3', 'm4a', 'mp4', 'flac'};
      if (optimizedFormats.contains(extension)) {
        final optimizedTags = await _readTagsOptimized(file, fileSize);
        return _extractArtworkFromTags(optimizedTags);
      }

      final fallbackTags = await _tagProcessor.getTagsFromByteArray(
        file.readAsBytes(),
      );
      return _extractArtworkFromTags(fallbackTags);
    } catch (e) {
      return null;
    }
  }

  static Future<List<Tag>> _readTagsOptimized(File file, int fileSize) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final header = await raf.read(10);
        if (header.length < 10) {
          await raf.close();
          return await _tagProcessor.getTagsFromByteArray(file.readAsBytes());
        }

        int tagSize = 0;
        var hasId3v2 = false;

        if (header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33) {
          hasId3v2 = true;
          tagSize = 10 +
              (((header[6] & 0x7F) << 21) |
                  ((header[7] & 0x7F) << 14) |
                  ((header[8] & 0x7F) << 7) |
                  (header[9] & 0x7F));
        }

        await raf.setPosition(0);
        final bytesToRead = hasId3v2 ? tagSize : min(65536, fileSize);
        final tagBytes = await raf.read(bytesToRead);

        Uint8List? id3v1Bytes;
        if (fileSize > 128) {
          await raf.setPosition(fileSize - 128);
          final tail = await raf.read(128);
          if (tail.length == 128 &&
              tail[0] == 0x54 &&
              tail[1] == 0x41 &&
              tail[2] == 0x47) {
            id3v1Bytes = tail;
          }
        }

        await raf.close();

        final Uint8List allBytes;
        if (id3v1Bytes != null) {
          allBytes = Uint8List(tagBytes.length + id3v1Bytes.length);
          allBytes.setAll(0, tagBytes);
          allBytes.setAll(tagBytes.length, id3v1Bytes);
        } else {
          allBytes = tagBytes;
        }

        return await _tagProcessor.getTagsFromByteArray(
          Future.value(allBytes),
        );
      } catch (e) {
        await raf.close();
        rethrow;
      }
    } catch (e) {
      return await _tagProcessor.getTagsFromByteArray(file.readAsBytes());
    }
  }

  static List<int>? _extractArtworkFromTags(List<Tag> tags) {
    for (final tag in tags) {
      final tagMap = tag.tags;
      final picture = _getTagValue(tagMap, [
        'picture',
        'APIC',
        'PIC',
        'METADATA_BLOCK_PICTURE',
      ]);

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
              try {
                final dynamic attachedPicture = imageData;
                final pictureData = attachedPicture.imageData;
                if (pictureData is List) {
                  return List<int>.from(pictureData);
                }
              } catch (_) {}
            }
          }
        }
      }
    }
    return null;
  }

  static dynamic _getTagValue(Map<String, dynamic> tagMap, List<String> keys) {
    for (final key in keys) {
      if (tagMap.containsKey(key)) {
        return tagMap[key];
      }
    }
    return null;
  }
}
