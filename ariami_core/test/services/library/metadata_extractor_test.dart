import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/mp3_duration_parser.dart';
import 'package:dart_tags/dart_tags.dart';
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
      expect(
          sanitizeTagText('G-Eazy\u0000'), equals(sanitizeTagText('G-Eazy')));
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

  group('MetadataExtractor generated ID3 regression fixtures', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_id3_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ID3v2.4 UTF-8 wins over equal-length lossy ID3v1 text', () async {
      final file = File('${tempDir.path}/cyrillic-v24.mp3');
      await file.writeAsBytes(_id3File(
        version: 4,
        frames: [
          _textFrame(4, 'TIT2', 'Матушка', utf16: false),
          _textFrame(4, 'TPE1', 'Татьяна Куртукова', utf16: false),
          _textFrame(4, 'TALB', 'Матушка', utf16: false),
        ],
        id3v1: _id3v1(
          title: '???????',
          artist: '??????? ?????????',
          album: '???????',
        ),
      ));

      final metadata = await MetadataExtractor().extractMetadata(file.path);

      expect(metadata.title, equals('Матушка'));
      expect(metadata.artist, equals('Татьяна Куртукова'));
      expect(metadata.album, equals('Матушка'));
    });

    test('ID3v2.3 UTF-16 preserves Romanian Unicode', () async {
      final file = File('${tempDir.path}/romanian-v23.mp3');
      const title = 'Și îngerii au demonii lor';
      await file.writeAsBytes(_id3File(
        version: 3,
        frames: [
          _textFrame(3, 'TIT2', title, utf16: true),
          _textFrame(3, 'TPE1', 'Dan Bittman', utf16: true),
          _textFrame(3, 'TALB', title, utf16: true),
        ],
      ));

      final metadata = await MetadataExtractor().extractMetadata(file.path);

      expect(metadata.title, equals(title));
      expect(metadata.artist, equals('Dan Bittman'));
      expect(metadata.album, equals(title));
    });

    test('ffprobe replaces only suspicious fields', () async {
      final file = File('${tempDir.path}/per-field-fallback.mp3');
      await file.writeAsBytes(_id3File(
        version: 4,
        frames: [
          _textFrame(4, 'TIT2', '???????', utf16: false),
          _textFrame(4, 'TPE1', 'Existing Artist', utf16: false),
          _textFrame(4, 'TALB', 'Existing Album', utf16: false),
        ],
      ));

      final extractor = MetadataExtractor(
        processRunner: (executable, arguments) async {
          if (arguments.length == 1 && arguments.first == '-version') {
            return ProcessResult(1, 0, 'ffprobe version test', '');
          }
          if (arguments.any((a) => a.startsWith('format_tags'))) {
            return ProcessResult(
              1,
              0,
              '{"format":{"tags":{"title":"Матушка",'
                  '"artist":"Probe Artist","album":"Probe Album"}}}',
              '',
            );
          }
          return ProcessResult(1, 0, '{}', '');
        },
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.title, equals('Матушка'));
      expect(metadata.artist, equals('Existing Artist'));
      expect(metadata.album, equals('Existing Album'));
    });

    test('ID3v2.4 embedded JPEG falls back to raw APIC parsing', () async {
      const jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9];
      final file = File('${tempDir.path}/jpeg-v24.mp3');
      await file.writeAsBytes(_id3File(
        version: 4,
        frames: [
          _textFrame(4, 'TIT2', 'JPEG cover', utf16: false),
          _apicFrame(4, 'image/jpeg', jpeg),
        ],
      ));
      final extractor = MetadataExtractor(
        tagProcessor: _NoArtworkTagProcessor(),
      );

      expect(await extractor.hasEmbeddedArtwork(file.path), isTrue);
      expect(await extractor.extractArtwork(file.path), equals(jpeg));
    });

    test('ID3v2.3 embedded PNG falls back to raw APIC parsing', () async {
      const png = <int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ];
      final file = File('${tempDir.path}/png-v23.mp3');
      await file.writeAsBytes(_id3File(
        version: 3,
        frames: [
          _textFrame(3, 'TIT2', 'PNG cover', utf16: true),
          _apicFrame(
            3,
            'image/png',
            png,
            utf16Description: true,
          ),
        ],
      ));
      final extractor = MetadataExtractor(
        tagProcessor: _NoArtworkTagProcessor(),
      );

      expect(await extractor.hasEmbeddedArtwork(file.path), isTrue);
      expect(await extractor.extractArtwork(file.path), equals(png));
    });
  });
}

class _FakeMp3DurationParser extends Mp3DurationParser {
  _FakeMp3DurationParser({required this.duration});

  final int? duration;

  @override
  Future<int?> getDuration(String filePath) async => duration;
}

class _NoArtworkTagProcessor extends TagProcessor {
  @override
  Future<List<Tag>> getTagsFromByteArray(
    Future<List<int>>? bytes, [
    List<TagType>? types,
  ]) async =>
      <Tag>[];
}

List<int> _id3File({
  required int version,
  required List<List<int>> frames,
  List<int>? id3v1,
}) {
  final body = <int>[
    ...frames.expand((frame) => frame),
    ...List<int>.filled(32, 0),
  ];
  return <int>[
    ...ascii.encode('ID3'),
    version,
    0,
    0,
    ..._syncSafe(body.length),
    ...body,
    0xFF,
    0xFB,
    0x90,
    0x64,
    ...?id3v1,
  ];
}

List<int> _textFrame(
  int version,
  String id,
  String value, {
  required bool utf16,
}) {
  final body = utf16
      ? <int>[1, 0xFF, 0xFE, ..._utf16le(value), 0, 0]
      : <int>[3, ...utf8.encode(value), 0];
  return _frame(version, id, body);
}

List<int> _apicFrame(
  int version,
  String mime,
  List<int> image, {
  bool utf16Description = false,
}) =>
    _frame(
      version,
      'APIC',
      utf16Description
          ? <int>[
              1,
              ...latin1.encode(mime),
              0,
              3,
              0xFF,
              0xFE,
              ..._utf16le('Cover'),
              0,
              0,
              ...image,
            ]
          : <int>[0, ...latin1.encode(mime), 0, 3, 0, ...image],
    );

List<int> _frame(int version, String id, List<int> body) => <int>[
      ...ascii.encode(id),
      ...(version == 4 ? _syncSafe(body.length) : _bigEndian(body.length)),
      0,
      0,
      ...body,
    ];

List<int> _syncSafe(int value) => <int>[
      (value >> 21) & 0x7F,
      (value >> 14) & 0x7F,
      (value >> 7) & 0x7F,
      value & 0x7F,
    ];

List<int> _bigEndian(int value) => <int>[
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

List<int> _utf16le(String value) => <int>[
      for (final codeUnit in value.codeUnits) ...[
        codeUnit & 0xFF,
        (codeUnit >> 8) & 0xFF,
      ],
    ];

List<int> _id3v1({
  required String title,
  required String artist,
  required String album,
}) {
  final bytes = List<int>.filled(128, 0);
  bytes.setRange(0, 3, ascii.encode('TAG'));
  _writeId3v1Field(bytes, 3, 30, title);
  _writeId3v1Field(bytes, 33, 30, artist);
  _writeId3v1Field(bytes, 63, 30, album);
  bytes.setRange(93, 97, ascii.encode('2022'));
  bytes[125] = 0;
  bytes[126] = 1;
  return bytes;
}

void _writeId3v1Field(
  List<int> target,
  int offset,
  int length,
  String value,
) {
  final encoded = latin1.encode(value);
  target.setRange(offset, offset + encoded.length.clamp(0, length), encoded);
}
