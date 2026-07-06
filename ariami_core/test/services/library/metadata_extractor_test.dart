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

  group('MetadataExtractor ffprobe tag fallback', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_meta_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('fills tags from ffprobe for formats dart_tags cannot parse',
        () async {
      // A FLAC-like file with no ID3 tags: dart_tags finds nothing.
      final file = File('${tempDir.path}/mystery.flac');
      await file.writeAsBytes(List<int>.filled(4096, 0x42));

      final extractor = MetadataExtractor(
        processRunner: (executable, arguments) async {
          if (arguments.length == 1 && arguments.first == '-version') {
            return ProcessResult(1, 0, 'ffprobe version test', '');
          }
          if (arguments.any((a) => a.startsWith('format_tags'))) {
            return ProcessResult(
              1,
              0,
              '{"format":{"duration":"245.3","bit_rate":"965000",'
                  '"tags":{"TITLE":"Real Title","ARTIST":"Real Artist",'
                  '"ALBUM":"Real Album","date":"2019-04-01","track":"3/12",'
                  '"disc":"1/2","GENRE":"Jazz","album_artist":"Real Band"}}}',
              '',
            );
          }
          // Bitrate/duration probes: return nothing useful.
          return ProcessResult(1, 0, '{}', '');
        },
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.title, equals('Real Title'));
      expect(metadata.artist, equals('Real Artist'));
      expect(metadata.album, equals('Real Album'));
      expect(metadata.albumArtist, equals('Real Band'));
      expect(metadata.genre, equals('Jazz'));
      expect(metadata.year, equals(2019));
      expect(metadata.trackNumber, equals(3));
      expect(metadata.discNumber, equals(1));
      expect(metadata.duration, equals(245),
          reason: 'duration should come from the same combined probe');
      expect(metadata.bitrate, equals(965));
    });

    test('falls back to filename parsing when ffprobe is unavailable',
        () async {
      final file = File('${tempDir.path}/01 - Some Artist - Some Song.flac');
      await file.writeAsBytes(List<int>.filled(4096, 0x42));

      final extractor = MetadataExtractor(
        processRunner: (executable, arguments) async {
          throw ProcessException(executable, arguments, 'not found', 127);
        },
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.title, equals('Some Song'));
      expect(metadata.artist, equals('Some Artist'));
      expect(metadata.trackNumber, equals(1));
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
