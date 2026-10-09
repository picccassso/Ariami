import 'dart:io';
import 'dart:typed_data';

import 'package:ariami_core/services/artwork/image_normalizer.dart';
import 'package:test/test.dart';

/// PNG signature plus an IHDR chunk header; enough for dimension parsing.
Uint8List _png(int width, int height, {int padding = 0}) {
  final data = ByteData(24 + padding);
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    data.setUint8(i, signature[i]);
  }
  data.setUint32(8, 13);
  data.setUint32(12, 0x49484452); // "IHDR"
  data.setUint32(16, width);
  data.setUint32(20, height);
  return data.buffer.asUint8List();
}

/// [_png] completed with a colour type and an IDAT chunk, preceded by a tRNS
/// chunk when [transparent].
Uint8List _opaquePng(int width, int height,
    {bool transparent = false, int padding = 0}) {
  List<int> chunk(String type, int length) => [
        0, 0, length >> 8, length & 0xFF, ...type.codeUnits,
        ...List.filled(length + 4, 0), // data + CRC
      ];
  return Uint8List.fromList([
    ..._png(width, height),
    8, 2, 0, 0, 0, ...List.filled(4, 0), // 8-bit RGB, rest of IHDR, CRC
    if (transparent) ...chunk('tRNS', 6),
    ...chunk('IDAT', padding),
  ]);
}

/// SOI, an APP0 segment, then a SOF0 frame header.
Uint8List _jpeg(int width, int height, {int padding = 0}) {
  final bytes = <int>[
    0xFF, 0xD8, // SOI
    0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0 (length 4 incl. itself)
    0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0, length, precision
    height >> 8, height & 0xFF, width >> 8, width & 0xFF,
    ...List.filled(10, 0),
    ...List.filled(padding, 0),
  ];
  return Uint8List.fromList(bytes);
}

/// [_jpeg] with an APP1 Exif segment whose IFD0 holds [orientation].
Uint8List _exifJpeg(int width, int height, int orientation,
    {bool little = false}) {
  List<int> u16(int v) => little ? [v & 0xFF, v >> 8] : [v >> 8, v & 0xFF];
  List<int> u32(int v) => little
      ? [...u16(v & 0xFFFF), ...u16(v >> 16)]
      : [...u16(v >> 16), ...u16(v & 0xFFFF)];
  final tiff = [
    ...(little ? [0x49, 0x49] : [0x4D, 0x4D]), ...u16(42), ...u32(8),
    ...u16(1), // one IFD0 entry: orientation, SHORT, count 1
    ...u16(0x0112), ...u16(3), ...u32(1), ...u16(orientation), 0, 0,
    ...u32(0),
  ];
  final app1 = [...'Exif'.codeUnits, 0, 0, ...tiff];
  final jpeg = _jpeg(width, height);
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE1,
    (app1.length + 2) >> 8,
    (app1.length + 2) & 0xFF,
    ...app1,
    ...jpeg.sublist(2),
  ]);
}

void main() {
  group('ImageNormalizer.imageDimensions', () {
    test('reads PNG and JPEG headers', () {
      expect(ImageNormalizer.imageDimensions(_png(2833, 2224), 'image/png'),
          (2833, 2224));
      expect(ImageNormalizer.imageDimensions(_jpeg(2984, 3984), 'image/jpeg'),
          (2984, 3984));
    });

    test('returns null for malformed, truncated, or unsupported data', () {
      expect(ImageNormalizer.imageDimensions([1, 2, 3], 'image/png'), isNull);
      expect(ImageNormalizer.imageDimensions([0xFF, 0xD8, 0xFF], 'image/jpeg'),
          isNull);
      expect(
          ImageNormalizer.imageDimensions(_png(10, 10), 'image/jpeg'), isNull);
      expect(
          ImageNormalizer.imageDimensions(_png(10, 10), 'image/webp'), isNull);
    });
  });

  group('ImageNormalizer.jpegOrientation', () {
    test('reads the EXIF tag in either byte order, defaulting to 1', () {
      expect(ImageNormalizer.jpegOrientation(_exifJpeg(10, 10, 6)), 6);
      expect(
          ImageNormalizer.jpegOrientation(_exifJpeg(10, 10, 8, little: true)),
          8);
      expect(ImageNormalizer.jpegOrientation(_jpeg(10, 10)), 1);
      expect(
          ImageNormalizer.imageDimensions(_exifJpeg(30, 20, 6), 'image/jpeg'),
          (30, 20));
    });

    test('returns null for a truncated Exif segment', () {
      final truncated = _exifJpeg(10, 10, 6).sublist(0, 20);
      expect(ImageNormalizer.jpegOrientation(truncated), isNull);
    });
  });

  group('ImageNormalizer.shrinkIfOversized', () {
    late int ffmpegCalls;
    late List<String> ffmpegArgs;

    /// Fake FFmpeg that "encodes" [output] for resize invocations.
    ImageNormalizer normalizer({
      Uint8List? output,
      int resizeExitCode = 0,
      bool available = true,
      bool throwOnRun = false,
    }) {
      ffmpegCalls = 0;
      return ImageNormalizer(processRunner: (executable, arguments) async {
        if (throwOnRun) throw const ProcessException('ffmpeg', []);
        if (arguments.length == 1 && arguments.single == '-version') {
          return ProcessResult(1, available ? 0 : 127, '', '');
        }
        ffmpegCalls++;
        ffmpegArgs = arguments;
        if (output != null) await File(arguments.last).writeAsBytes(output);
        return ProcessResult(2, resizeExitCode, '', '');
      });
    }

    Future<Uint8List?> shrink(ImageNormalizer n, Uint8List bytes,
            {String type = 'image/jpeg', int max = 512}) async =>
        (await n.shrinkIfOversized(bytes, type, maxDimension: max))?.bytes;

    test('skips images already within bounds without running FFmpeg', () async {
      final n = normalizer(output: _jpeg(100, 100));
      expect(await shrink(n, _jpeg(512, 400)), isNull);
      expect(await shrink(n, _png(300, 512), type: 'image/png'), isNull);
      expect(ffmpegCalls, 0);
    });

    test('skips unsupported formats and unreadable headers', () async {
      final n = normalizer(output: _jpeg(100, 100));
      expect(await shrink(n, _png(3000, 3000), type: 'image/webp'), isNull);
      expect(await shrink(n, Uint8List.fromList([1, 2, 3])), isNull);
      expect(ffmpegCalls, 0);
    });

    test(
        'returns the resized output and requests a bounded, same-format '
        'file', () async {
      final small = _jpeg(512, 384);
      final n = normalizer(output: small);
      final result = await shrink(n, _jpeg(2000, 1500, padding: 5000));
      expect(result, small);
      expect(ffmpegArgs.last, endsWith('.jpg'));
      expect(ffmpegArgs,
          contains('scale=512:512:force_original_aspect_ratio=decrease'));

      final png = normalizer(output: _png(300, 200));
      await shrink(png, _png(2000, 1500, padding: 5000), type: 'image/png');
      expect(ffmpegArgs.last, endsWith('.png'));
    });

    test('applies EXIF rotation explicitly instead of FFmpeg autorotate',
        () async {
      final n = normalizer(output: _jpeg(384, 512));
      await shrink(n, _exifJpeg(2000, 1500, 6));
      expect(ffmpegArgs, contains('-noautorotate'));
      expect(
          ffmpegArgs,
          contains(
              'transpose=1,scale=512:512:force_original_aspect_ratio=decrease'));

      ffmpegCalls = 0;
      // An unknown orientation keeps the original rather than guessing.
      expect(await shrink(n, _exifJpeg(2000, 1500, 9)), isNull);
      expect(ffmpegCalls, 0);
    });

    test('keeps the original when the result is not smaller or not bounded',
        () async {
      final source = _jpeg(2000, 1500, padding: 100);
      expect(
          await shrink(
              normalizer(output: _jpeg(512, 384, padding: 500)), source),
          isNull);
      expect(
          await shrink(normalizer(output: _jpeg(1000, 750)), source), isNull);
      expect(
          await shrink(normalizer(output: Uint8List.fromList([1, 2])), source),
          isNull);
    });

    test('re-encodes an opaque PNG as JPEG only when allowed', () async {
      final source = _opaquePng(800, 600, padding: 5000);
      final jpeg = _jpeg(800, 600);
      final n = normalizer(output: jpeg);

      expect(await shrink(n, source, type: 'image/png', max: 1200), isNull);
      expect(ffmpegCalls, 0);

      final result = await n.shrinkIfOversized(source, 'image/png',
          maxDimension: 1200, jpegForOpaquePng: true);
      expect(result?.bytes, jpeg);
      expect(result?.contentType, 'image/jpeg');
      expect(ffmpegArgs.last, endsWith('.jpg'));
      expect(ffmpegArgs, isNot(contains('-vf'))); // within bounds: no scale

      // Transparent PNGs stay PNG.
      expect(
          await n.shrinkIfOversized(
              _opaquePng(800, 600, transparent: true), 'image/png',
              maxDimension: 1200, jpegForOpaquePng: true),
          isNull);
    });

    test('keeps the original when FFmpeg is missing or fails', () async {
      final source = _jpeg(2000, 1500, padding: 5000);
      expect(await shrink(normalizer(available: false), source), isNull);
      expect(await shrink(normalizer(throwOnRun: true), source), isNull);
      expect(ffmpegCalls, 0);
      expect(
          await shrink(
              normalizer(output: _jpeg(512, 384), resizeExitCode: 1), source),
          isNull);
      expect(await shrink(normalizer(), source), isNull); // no output written
    });
  });
}
