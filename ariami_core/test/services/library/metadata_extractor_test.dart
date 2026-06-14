import 'dart:io';

import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/mp3_duration_parser.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeTagText', () {
    test('strips trailing NUL terminators from NUL-padded ID3v1 fields', () {
      expect(sanitizeTagText('G-Eazy\u0000'), equals('G-Eazy'));
      expect(sanitizeTagText('These Things Happen\u0000\u0000'),
          equals('These Things Happen'));
    });

    test('strips zero-width and BOM format characters', () {
      expect(sanitizeTagText('G-Eazy\u200b'), equals('G-Eazy'));
      expect(sanitizeTagText('\ufeffG-Eazy'), equals('G-Eazy'));
    });

    test('trims surrounding whitespace', () {
      expect(sanitizeTagText('  G-Eazy  '), equals('G-Eazy'));
    });

    test('leaves clean names untouched', () {
      expect(sanitizeTagText('G-Eazy'), equals('G-Eazy'));
      expect(sanitizeTagText('Beyoncé'), equals('Beyoncé'));
    });

    test('a NUL-padded and a clean variant normalize to the same value', () {
      // This is the exact case that fragmented the artist stats: the album
      // track carried a NUL terminator while the standalone single did not.
      expect(sanitizeTagText('G-Eazy\u0000'), equals(sanitizeTagText('G-Eazy')));
    });
  });

  group('MetadataExtractor.extractDuration', () {
    test('prefers Dart MP3 parser before ffprobe for mp3 files', () async {
      var ffprobeCalls = 0;
      final extractor = MetadataExtractor(
        mp3DurationParser: _FakeMp3DurationParser(duration: 213),
        processRunner: (executable, arguments) async {
          ffprobeCalls++;
          return ProcessResult(1, 0, '{"format":{"duration":"999.0"}}', '');
        },
      );

      final duration = await extractor.extractDuration('song.mp3');

      expect(duration, equals(213));
      expect(ffprobeCalls, equals(0));
    });

    test('falls back to ffprobe when the MP3 parser cannot resolve duration',
        () async {
      final calls = <String>[];
      final extractor = MetadataExtractor(
        mp3DurationParser: _FakeMp3DurationParser(duration: null),
        processRunner: (executable, arguments) async {
          calls.add(arguments.join(' '));
          if (arguments.length == 1 && arguments.first == '-version') {
            return ProcessResult(1, 0, 'ffprobe version test', '');
          }
          return ProcessResult(1, 0, '{"format":{"duration":"244.4"}}', '');
        },
      );

      final duration = await extractor.extractDuration('song.mp3');

      expect(duration, equals(244));
      expect(calls, hasLength(2));
      expect(calls.first, equals('-version'));
      expect(calls.last, contains('format=duration'));
    });
  });
}

class _FakeMp3DurationParser extends Mp3DurationParser {
  _FakeMp3DurationParser({required this.duration});

  final int? duration;

  @override
  Future<int?> getDuration(String filePath) async => duration;
}
