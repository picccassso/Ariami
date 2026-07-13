import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  group('MetadataExtractor hardening', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_hardening_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ID3v2 precedence is deterministic even when tags arrive first',
        () async {
      final file = await _dummyFile(tempDir, 'precedence.mp3');
      final extractor = MetadataExtractor(
        tagProcessor: _StaticTagProcessor([
          _tag('2.4.0', {
            'title': 'Бог',
            'artist': 'Татьяна Куртукова',
            'album': 'У истока',
          }),
          _tag('1.1', {
            'title': 'Long legacy title',
            'artist': 'Long legacy artist',
            'album': 'Long legacy album',
          }),
        ]),
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.title, 'Бог');
      expect(metadata.artist, 'Татьяна Куртукова');
      expect(metadata.album, 'У истока');
    });

    test('preserves emoji and NUL-separated multiple artists', () async {
      final file = await _dummyFile(tempDir, 'unicode.mp3');
      final extractor = MetadataExtractor(
        tagProcessor: _StaticTagProcessor([
          _tag('2.4.0', {
            'title': '🎵 Привет lume',
            'artist': 'Artist A\u0000Artist B',
            'album': 'Și îngerii ✨',
            'TPE2': 'Various Artists',
            'genre': 'Pop; Electronic',
          }),
        ]),
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.title, '🎵 Привет lume');
      expect(metadata.artist, 'Artist A; Artist B');
      expect(metadata.album, 'Și îngerii ✨');
      expect(metadata.albumArtist, 'Various Artists');
      expect(metadata.genre, 'Pop; Electronic');
    });

    test('rejects placeholders and oversized text without logging values',
        () async {
      final file = await _dummyFile(tempDir, 'rejected.mp3');
      final oversized = List.filled(5000, 'x').join();
      final diagnostics = <String>[];
      final extractor = MetadataExtractor(
        tagProcessor: _StaticTagProcessor([
          _tag('2.4.0', {
            'title': oversized,
            'artist': 'Bad\uFFFDArtist',
            'album': '<unknown>',
          }),
        ]),
        processRunner: _ffprobeRunner(tags: {
          'title': 'Recovered title',
          'artist': 'Recovered artist',
          'album': 'Recovered album',
        }),
        diagnosticLogger: diagnostics.add,
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.title, 'Recovered title');
      expect(metadata.artist, 'Recovered artist');
      expect(metadata.album, 'Recovered album');
      expect(diagnostics, isNotEmpty);
      expect(diagnostics.every((line) => !line.contains(oversized)), isTrue);
      expect(diagnostics.every((line) => !line.contains('Bad\uFFFDArtist')),
          isTrue);
      expect(diagnostics.every((line) => !line.contains('<unknown>')), isTrue);
    });

    test('duplicate ID3v2 frames resolve consistently without crashing',
        () async {
      final file = File('${tempDir.path}/duplicate-v24.mp3');
      await file.writeAsBytes(_id3File(
        version: 4,
        frames: [
          _textFrame(4, 'TIT2', 'First title', utf16: false),
          _textFrame(4, 'TIT2', 'Second title', utf16: false),
          _textFrame(4, 'TPE1', 'Artist', utf16: false),
          _textFrame(4, 'TALB', 'Album', utf16: false),
        ],
      ));

      final metadata = await MetadataExtractor().extractMetadata(file.path);

      expect(metadata.title, 'Second title');
      expect(metadata.artist, 'Artist');
      expect(metadata.album, 'Album');
    });

    test('FLAC Vorbis comments preserve fields and parse totals safely',
        () async {
      final file = await _dummyFile(tempDir, 'vorbis.flac');
      final extractor = MetadataExtractor(
        processRunner: _ffprobeRunner(
          tags: {
            'TITLE': 'Flac 🎧',
            'ARTIST': 'Artist A; Artist B',
            'ALBUM': 'Album șapte',
            'ALBUM_ARTIST': 'Album Artist',
            'GENRE': 'Rock; Pop',
            'DATE': '2024-02-29',
            'TRACKNUMBER': '3/12',
            'DISCNUMBER': '2/3',
          },
          duration: 245.4,
          bitrate: 900000,
        ),
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.title, 'Flac 🎧');
      expect(metadata.artist, 'Artist A; Artist B');
      expect(metadata.album, 'Album șapte');
      expect(metadata.albumArtist, 'Album Artist');
      expect(metadata.genre, 'Rock; Pop');
      expect(metadata.year, 2024);
      expect(metadata.trackNumber, 3);
      expect(metadata.discNumber, 2);
      expect(metadata.duration, 245);
      expect(metadata.bitrate, 900);
    });

    test('M4A atoms map album artist, date, track and disc fields', () async {
      final file = await _dummyFile(tempDir, 'atoms.m4a');
      final extractor = MetadataExtractor(
        processRunner: _ffprobeRunner(tags: {
          'title': 'Atom title',
          'artist': 'One & Two',
          'album': 'Atom album',
          'album_artist': 'Atom album artist',
          'date': '1999',
          'track': '8/10',
          'disc': '1/2',
          'genre': 'Alternative',
        }),
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.albumArtist, 'Atom album artist');
      expect(metadata.year, 1999);
      expect(metadata.trackNumber, 8);
      expect(metadata.discNumber, 1);
      expect(metadata.genre, 'Alternative');
    });

    test('OGG partial metadata remains partial and valid', () async {
      final file = await _dummyFile(tempDir, 'partial.ogg');
      final extractor = MetadataExtractor(
        processRunner: _ffprobeRunner(tags: {'title': 'Only a title'}),
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.title, 'Only a title');
      expect(metadata.artist, isNull);
      expect(metadata.album, isNull);
    });

    test('WAV with no metadata falls back to filename and keeps probe facts',
        () async {
      final file = await _dummyFile(tempDir, 'No Metadata.wav');
      final extractor = MetadataExtractor(
        processRunner: _ffprobeRunner(
          tags: const {},
          duration: 12.2,
          bitrate: 1411200,
        ),
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.title, 'No Metadata');
      expect(metadata.artist, isNull);
      expect(metadata.duration, 12);
      expect(metadata.bitrate, 1411);
    });

    test('no-external-tools mode never invokes ffmpeg or ffprobe', () async {
      final file = await _dummyFile(tempDir, 'Offline Metadata.flac');
      var textProcessCalls = 0;
      var binaryProcessCalls = 0;
      final extractor = MetadataExtractor(
        externalToolsEnabled: false,
        processRunner: (executable, arguments) async {
          textProcessCalls++;
          throw StateError('external text process invoked');
        },
        binaryProcessRunner: (executable, arguments) async {
          binaryProcessCalls++;
          throw StateError('external binary process invoked');
        },
      );

      final metadata = await extractor.extractMetadataWithDuration(file.path);

      expect(metadata.title, 'Offline Metadata');
      expect(metadata.artist, isNull);
      expect(await extractor.hasEmbeddedArtwork(file.path), isFalse);
      expect(await extractor.extractArtwork(file.path), isNull);
      expect(textProcessCalls, 0);
      expect(binaryProcessCalls, 0);
    });

    test('FLAC attached artwork falls back through ffmpeg', () async {
      const jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9];
      final file = await _dummyFile(tempDir, 'art.flac');
      final extractor = MetadataExtractor(
        processRunner: _ffprobeRunner(
          tags: const {},
          attachedPicture: true,
        ),
        binaryProcessRunner: (executable, arguments) async => ProcessResult(
          1,
          0,
          Uint8List.fromList(jpeg),
          '',
        ),
      );

      expect(await extractor.hasEmbeddedArtwork(file.path), isTrue);
      expect(await extractor.extractArtwork(file.path), jpeg);
    });

    test('malformed picture entry does not hide a later valid cover', () async {
      const jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9];
      final file = await _dummyFile(tempDir, 'multiple-pictures.mp3');
      final extractor = MetadataExtractor(
        tagProcessor: _StaticTagProcessor([
          _tag('2.4.0', {
            'picture': {
              'Other': 'malformed',
              'Cover (front)': jpeg,
            },
          }),
        ]),
      );

      expect(await extractor.hasEmbeddedArtwork(file.path), isTrue);
      expect(await extractor.extractArtwork(file.path), jpeg);
    });

    test('malformed oversized ID3 and parser timeout fall back safely',
        () async {
      final file = File('${tempDir.path}/malformed.mp3');
      await file.writeAsBytes(<int>[
        ...ascii.encode('ID3'),
        4,
        0,
        0,
        ..._syncSafe(70 * 1024 * 1024),
        ...List<int>.filled(256, 0),
      ]);
      final diagnostics = <String>[];
      final extractor = MetadataExtractor(
        tagProcessor: _HangingTagProcessor(),
        tagReadTimeout: const Duration(milliseconds: 10),
        processRunner: _ffprobeRunner(tags: {
          'title': 'Recovered',
          'artist': 'Artist',
          'album': 'Album',
        }),
        diagnosticLogger: diagnostics.add,
      );

      final metadata = await extractor.extractMetadata(file.path);

      expect(metadata.title, 'Recovered');
      expect(metadata.artist, 'Artist');
      expect(diagnostics.any((line) => line.contains('id3_size_rejected')),
          isTrue);
      expect(
          diagnostics.any((line) => line.contains('dart_tags_failed')), isTrue);
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

class _StaticTagProcessor extends TagProcessor {
  _StaticTagProcessor(this.values);

  final List<Tag> values;

  @override
  Future<List<Tag>> getTagsFromByteArray(
    Future<List<int>>? bytes, [
    List<TagType>? types,
  ]) async =>
      values;
}

class _HangingTagProcessor extends TagProcessor {
  @override
  Future<List<Tag>> getTagsFromByteArray(
    Future<List<int>>? bytes, [
    List<TagType>? types,
  ]) =>
      Completer<List<Tag>>().future;
}

Tag _tag(String version, Map<String, dynamic> values) => Tag()
  ..type = 'ID3'
  ..version = version
  ..tags = values;

Future<File> _dummyFile(Directory directory, String name) async {
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(List<int>.filled(256, 0));
  return file;
}

ProcessRunner _ffprobeRunner({
  required Map<String, String> tags,
  double? duration,
  int? bitrate,
  bool attachedPicture = false,
}) {
  return (executable, arguments) async {
    if (arguments.length == 1 && arguments.first == '-version') {
      return ProcessResult(1, 0, 'ffprobe version test', '');
    }
    if (arguments.any((argument) => argument.startsWith('format_tags'))) {
      return ProcessResult(
        1,
        0,
        jsonEncode({
          'format': {
            if (duration != null) 'duration': duration.toString(),
            if (bitrate != null) 'bit_rate': bitrate.toString(),
            'tags': tags,
          },
          'streams': [
            {
              if (bitrate != null) 'bit_rate': bitrate.toString(),
              'disposition': {'attached_pic': attachedPicture ? 1 : 0},
            },
          ],
        }),
        '',
      );
    }
    if (arguments.contains('stream=bit_rate')) {
      return ProcessResult(
        1,
        0,
        jsonEncode({
          'streams': [
            {if (bitrate != null) 'bit_rate': bitrate.toString()},
          ],
        }),
        '',
      );
    }
    return ProcessResult(1, 0, '{}', '');
  };
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
