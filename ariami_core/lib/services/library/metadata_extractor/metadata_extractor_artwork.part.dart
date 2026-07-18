part of '../metadata_extractor.dart';

extension _MetadataExtractorArtworkPart on MetadataExtractor {
  /// Cheap check for embedded cover art without reading image bytes.
  Future<bool> _hasEmbeddedArtworkImpl(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final extension = p.extension(filePath).toLowerCase();
      final fileStat = await file.stat();
      final tags = await _readTagsOptimized(file, fileStat.size);
      if (_extractArtworkFromTags(tags) != null) return true;

      if (extension == '.mp3') {
        if (await _readId3v2Artwork(file, extractBytes: false) != null) {
          return true;
        }
      }

      final probed = await _probeWithFfprobe(filePath);
      return probed?.hasAttachedPicture ?? false;
    } catch (e) {
      _diagnose(
        'artwork_detection_failed format=${_safeFormat(filePath)} '
        'error=${e.runtimeType}',
      );
      return false;
    }
  }

  /// Returns a sidecar artwork path in the album directory of [songFilePath].
  String? _findSidecarArtworkForSongImpl(String songFilePath) {
    final albumDir = p.dirname(songFilePath);
    return findAlbumSidecarArtworkPath(albumDir);
  }

  /// Extracts album artwork from a single audio file (lazy extraction)
  ///
  /// This is called on-demand when artwork is requested, not during scan.
  /// Returns the artwork bytes or null if no artwork found.
  Future<List<int>?> _extractArtworkImpl(String filePath) async {
    try {
      final file = File(filePath);
      final fileStat = await file.stat();
      final fileSize = fileStat.size;
      final extension = p.extension(filePath).toLowerCase();

      final optimizedTags = await _readTagsOptimized(file, fileSize);
      final parsedArtwork = _extractArtworkFromTags(optimizedTags);
      if (parsedArtwork != null) return parsedArtwork;

      if (extension == '.mp3') {
        final rawArtwork = await _readId3v2Artwork(file, extractBytes: true);
        if (rawArtwork != null) {
          _diagnose('artwork_raw_id3_fallback format=.mp3');
          return rawArtwork;
        }
      }

      final probed = await _probeWithFfprobe(filePath);
      if (probed?.hasAttachedPicture ?? false) {
        final artwork = await _extractArtworkWithFfmpeg(filePath);
        if (artwork != null) {
          _diagnose('artwork_ffmpeg_fallback format=${_safeFormat(filePath)}');
          return artwork;
        }
      }
      return null;
    } catch (e) {
      _diagnose(
        'artwork_extract_failed format=${_safeFormat(filePath)} '
        'error=${e.runtimeType}',
      );
      return null;
    }
  }

  List<int>? _extractArtworkFromTags(List<Tag> tags) {
    for (final tag in tags) {
      final tagMap = tag.tags;
      final picture = _getTagValue(tagMap, [
        'picture',
        'APIC',
        'PIC',
        'METADATA_BLOCK_PICTURE',
      ]);

      if (picture != null) {
        final direct = _coerceArtworkBytes(picture);
        if (direct != null) return direct;

        if (picture is Map) {
          final entries = picture.entries.toList()
            ..sort((a, b) {
              final aFront = a.key.toString().toLowerCase().contains('front');
              final bFront = b.key.toString().toLowerCase().contains('front');
              if (aFront == bFront) return 0;
              return aFront ? -1 : 1;
            });
          for (final entry in entries) {
            final bytes = _coerceArtworkBytes(entry.value);
            if (bytes != null) return bytes;

            try {
              final dynamic attachedPicture = entry.value;
              final attachedBytes =
                  _coerceArtworkBytes(attachedPicture.imageData);
              if (attachedBytes != null) return attachedBytes;
            } catch (_) {
              // Try the next picture entry or the external fallback.
            }
          }
        }
      }
    }
    return null;
  }

  List<int>? _coerceArtworkBytes(dynamic value) {
    if (value is Uint8List) return _validatedArtwork(value);
    if (value is List && value.every((element) => element is int)) {
      return _validatedArtwork(value.cast<int>());
    }
    return null;
  }

  Future<List<int>?> _extractArtworkWithFfmpeg(String filePath) async {
    if (!_externalToolsEnabled) return null;
    try {
      final result = await _binaryProcessRunner('ffmpeg', [
        '-v',
        'error',
        '-i',
        filePath,
        '-map',
        '0:v:0',
        '-frames:v',
        '1',
        '-c:v',
        'copy',
        '-f',
        'image2pipe',
        'pipe:1',
      ]).timeout(_processTimeout);
      if (result.exitCode != 0) return null;
      final stdout = result.stdout;
      if (stdout is Uint8List) return _validatedArtwork(stdout);
      if (stdout is List<int>) return _validatedArtwork(stdout);
    } catch (e) {
      _diagnose(
        'ffmpeg_artwork_failed format=${_safeFormat(filePath)} '
        'error=${e.runtimeType}',
      );
    }
    return null;
  }

  List<int>? _validatedArtwork(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > MetadataExtractor._maxArtworkBytes) {
      return null;
    }
    const jpeg = [0xFF, 0xD8];
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (!_startsWithBytes(bytes, jpeg, 0) && !_startsWithBytes(bytes, png, 0)) {
      return null;
    }
    return List<int>.from(bytes);
  }

  /// Reads a valid ID3v2 APIC frame directly when dart_tags omits it. This is
  /// bounded to the declared tag section and supports v2.3/v2.4 frame sizes.
  /// In detection mode an empty list is returned once valid image bytes are
  /// found, avoiding a second copy of the full cover.
  Future<List<int>?> _readId3v2Artwork(
    File file, {
    required bool extractBytes,
  }) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final header = await raf.read(10);
      if (header.length != 10 ||
          header[0] != 0x49 ||
          header[1] != 0x44 ||
          header[2] != 0x33) {
        return null;
      }

      final majorVersion = header[3];
      if (majorVersion != 3 && majorVersion != 4) return null;

      final tagSize = _syncSafeInt(header, 6);
      final fileSize = await file.length();
      if (tagSize <= 0 ||
          tagSize > fileSize - 10 ||
          tagSize > MetadataExtractor._maxTagSectionBytes) {
        return null;
      }

      await raf.setPosition(10);
      final body = await raf.read(tagSize);
      var offset = 0;

      var frameCount = 0;
      while (offset + 10 <= body.length && frameCount++ < 10000) {
        final frameId = String.fromCharCodes(body.sublist(offset, offset + 4));
        if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(frameId)) break;

        final frameSize = majorVersion == 4
            ? _syncSafeInt(body, offset + 4)
            : _bigEndianInt(body, offset + 4);
        final frameStart = offset + 10;
        final frameEnd = frameStart + frameSize;
        if (frameSize <= 0 || frameEnd > body.length) break;

        if (frameId == 'APIC') {
          final image = _extractApicBytes(
            body.sublist(frameStart, frameEnd),
            extractBytes: extractBytes,
          );
          if (image != null) return image;
        }

        offset = frameEnd;
      }
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
    return null;
  }

  List<int>? _extractApicBytes(
    List<int> frame, {
    required bool extractBytes,
  }) {
    if (frame.length < 5) return null;

    final mimeEnd = frame.indexOf(0, 1);
    if (mimeEnd < 0 || mimeEnd + 2 >= frame.length) return null;

    final encoding = frame[0];
    var imageStart = mimeEnd + 2;
    if (encoding == 1 || encoding == 2) {
      imageStart = _indexOfUtf16Terminator(frame, imageStart);
      if (imageStart < 0) return null;
      imageStart += 2;
    } else {
      imageStart = frame.indexOf(0, imageStart);
      if (imageStart < 0) return null;
      imageStart += 1;
    }

    const jpeg = [0xFF, 0xD8];
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (!_startsWithBytes(frame, jpeg, imageStart) &&
        !_startsWithBytes(frame, png, imageStart)) {
      return null;
    }

    final image = _validatedArtwork(frame.sublist(imageStart));
    if (image == null) return null;
    return extractBytes ? image : const <int>[];
  }

  int _syncSafeInt(List<int> bytes, int offset) =>
      ((bytes[offset] & 0x7F) << 21) |
      ((bytes[offset + 1] & 0x7F) << 14) |
      ((bytes[offset + 2] & 0x7F) << 7) |
      (bytes[offset + 3] & 0x7F);

  int _bigEndianInt(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  int _indexOfUtf16Terminator(List<int> bytes, int start) {
    for (var i = start; i + 1 < bytes.length; i += 2) {
      if (bytes[i] == 0 && bytes[i + 1] == 0) return i;
    }
    return -1;
  }

  bool _startsWithBytes(List<int> bytes, List<int> pattern, int offset) {
    if (offset < 0 || offset + pattern.length > bytes.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[offset + i] != pattern[i]) return false;
    }
    return true;
  }
}
