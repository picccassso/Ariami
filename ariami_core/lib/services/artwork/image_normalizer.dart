import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'ffmpeg_probe.dart';

/// Shrinks oversized user-uploaded images (avatars, playlist covers, artist
/// photos) so clients never download or decode camera-resolution originals,
/// and can re-encode opaque PNG covers as much smaller JPEGs.
///
/// Every failure path (unsupported format, unreadable header, FFmpeg missing,
/// failing or timing out) means "keep the original", so callers can always
/// fall back to storing the upload unchanged.
class ImageNormalizer {
  ImageNormalizer({ArtworkProcessRunner? processRunner})
      : _runProcess = processRunner ??
            ((executable, arguments) => Process.run(executable, arguments)) {
    _ffmpeg = FfmpegProbe(_runProcess);
  }

  static const int avatarMaxDimension = 512;
  static const int coverMaxDimension = 1200;

  /// Formats re-encoded (PNG stays PNG unless it is opaque and the caller
  /// allows JPEG). Anything else, e.g. WebP, is stored as uploaded.
  static const Map<String, String> _extensions = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
  };

  /// FFmpeg filters that apply each EXIF orientation (1-8). Applied
  /// explicitly with `-noautorotate`, because older FFmpeg ignores the JPEG
  /// tag yet drops it on re-encode, which would leave photos sideways.
  static const List<String> _orientationFilters = [
    '', 'hflip', 'hflip,vflip', 'vflip', //
    'transpose=0', 'transpose=1', 'transpose=3', 'transpose=2',
  ];

  final ArtworkProcessRunner _runProcess;
  late final FfmpegProbe _ffmpeg;

  /// Returns [bytes] downscaled to a longest edge of at most [maxDimension],
  /// or null when the original should be kept (already within bounds,
  /// unsupported, or FFmpeg could not produce a smaller, valid result).
  ///
  /// With [jpegForOpaquePng], a PNG without transparency is re-encoded as JPEG
  /// even when within bounds: lossless PNG photos are often several MB.
  Future<({Uint8List bytes, String contentType})?> shrinkIfOversized(
    List<int> bytes,
    String contentType, {
    required int maxDimension,
    bool jpegForOpaquePng = false,
  }) async {
    if (!_extensions.containsKey(contentType)) return null;
    final dimensions = imageDimensions(bytes, contentType);
    if (dimensions == null) return null;
    final oversized = max(dimensions.$1, dimensions.$2) > maxDimension;
    final outputType =
        jpegForOpaquePng && contentType == 'image/png' && isOpaquePng(bytes)
            ? 'image/jpeg'
            : contentType;
    if (!oversized && outputType == contentType) return null;
    final orientation =
        contentType == 'image/jpeg' ? jpegOrientation(bytes) : 1;
    if (orientation == null || orientation < 1 || orientation > 8) return null;
    if (!await _ffmpeg.isAvailable()) return null;

    final tempDir = await Directory.systemTemp.createTemp('ariami_image_');
    try {
      final input = File('${tempDir.path}/input');
      final output = File('${tempDir.path}/output.${_extensions[outputType]}');
      await input.writeAsBytes(bytes);
      final filters = [
        _orientationFilters[orientation - 1],
        if (oversized)
          'scale=$maxDimension:$maxDimension'
              ':force_original_aspect_ratio=decrease',
      ].where((filter) => filter.isNotEmpty).join(',');

      final result = await _runProcess('ffmpeg', [
        '-y',
        '-noautorotate',
        '-i', input.path,
        if (filters.isNotEmpty) ...['-vf', filters],
        '-frames:v', '1',
        '-q:v', '3', // JPEG quality; ignored for PNG
        output.path,
      ]).timeout(
        const Duration(seconds: 10),
        onTimeout: () => ProcessResult(-1, -1, '', 'Timeout'),
      );
      if (result.exitCode != 0 || !await output.exists()) {
        print('[ImageNormalizer] FFmpeg failed (exit ${result.exitCode})');
        return null;
      }

      final shrunk = await output.readAsBytes();
      final shrunkDimensions = imageDimensions(shrunk, outputType);
      if (shrunk.length >= bytes.length ||
          shrunkDimensions == null ||
          max(shrunkDimensions.$1, shrunkDimensions.$2) > maxDimension) {
        return null;
      }
      print('[ImageNormalizer] ${dimensions.$1}x${dimensions.$2} -> '
          '${shrunkDimensions.$1}x${shrunkDimensions.$2}: '
          '${(bytes.length / 1024).round()} KB -> '
          '${(shrunk.length / 1024).round()} KB ($outputType)');
      return (bytes: shrunk, contentType: outputType);
    } catch (e) {
      print('[ImageNormalizer] Resize error - $e');
      return null;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Reads (width, height) from the PNG IHDR or the first JPEG SOF header
  /// without decoding the image; null when unsupported or malformed.
  static (int, int)? imageDimensions(List<int> bytes, String contentType) {
    int be16(int i) => (bytes[i] << 8) | bytes[i + 1];
    int be32(int i) => (be16(i) << 16) | be16(i + 2);

    if (contentType == 'image/png') {
      // 8-byte signature, then the IHDR chunk: length, "IHDR", width, height.
      if (bytes.length < 24 || be32(12) != 0x49484452) return null;
      return (be32(16), be32(20));
    }

    if (contentType != 'image/jpeg') return null;
    for (final (marker, at) in _jpegSegments(bytes)) {
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        // SOFn: length, precision, height, width.
        return at + 7 <= bytes.length ? (be16(at + 5), be16(at + 3)) : null;
      }
    }
    return null;
  }

  /// Whether a PNG can't carry transparency: greyscale, RGB or palette colour
  /// with no tRNS chunk before the image data.
  static bool isOpaquePng(List<int> bytes) {
    if (bytes.length < 26 || !const {0, 2, 3}.contains(bytes[25])) {
      return false;
    }
    var i = 8; // past the signature
    while (i + 8 <= bytes.length) {
      final type = String.fromCharCodes(bytes.sublist(i + 4, i + 8));
      if (type == 'tRNS') return false;
      if (type == 'IDAT') return true;
      final length = (bytes[i] << 24) |
          (bytes[i + 1] << 16) |
          (bytes[i + 2] << 8) |
          bytes[i + 3];
      i += 12 + length; // length, type, data, CRC
    }
    return false;
  }

  /// EXIF orientation (1-8) of a JPEG: 1 when it carries none, null when the
  /// tag can't be read.
  static int? jpegOrientation(List<int> bytes) {
    for (final (marker, at) in _jpegSegments(bytes)) {
      try {
        // APP1 "Exif\0\0", then a TIFF header whose IFD0 may hold 0x0112.
        if (marker != 0xE1 ||
            String.fromCharCodes(bytes.sublist(at + 2, at + 6)) != 'Exif') {
          continue;
        }
        final tiff = at + 8;
        final little = bytes[tiff] == 0x49; // "II"
        int u16(int o) => little
            ? bytes[tiff + o] | bytes[tiff + o + 1] << 8
            : bytes[tiff + o] << 8 | bytes[tiff + o + 1];
        int u32(int o) =>
            little ? u16(o) | u16(o + 2) << 16 : u16(o) << 16 | u16(o + 2);
        final ifd = u32(4);
        for (var entry = 0; entry < u16(ifd); entry++) {
          final offset = ifd + 2 + entry * 12;
          if (u16(offset) == 0x0112) return u16(offset + 8);
        }
        return 1;
      } on RangeError {
        return null;
      }
    }
    return 1;
  }

  /// (marker, offset of its length field) for each JPEG segment before the
  /// scan data; ends early on malformed data.
  static Iterable<(int, int)> _jpegSegments(List<int> bytes) sync* {
    var i = 2; // past the SOI marker
    while (i + 4 <= bytes.length && bytes[i] == 0xFF) {
      final marker = bytes[i + 1];
      if (marker == 0xFF) {
        i++; // fill byte
      } else if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
        i += 2; // standalone marker without a length
      } else if (marker == 0xDA) {
        return; // scan data reached
      } else {
        yield (marker, i + 2);
        i += 2 + ((bytes[i + 2] << 8) | bytes[i + 3]);
      }
    }
  }
}
