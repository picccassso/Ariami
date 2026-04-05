import 'dart:io';

import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/mp3_duration_parser.dart';
import 'package:test/test.dart';

void main() {
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
