import 'dart:convert';
import 'dart:io';
import 'package:ariami_core/models/lyrics_models.dart';
import 'package:ariami_core/services/library/lyrics_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ariami_lyrics_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LyricsExtractor sidecar detection', () {
    test('finds sidecar .lrc matching audio base name', () async {
      final audioFile = File(p.join(tempDir.path, 'track01.mp3'));
      await audioFile.writeAsString('audio dummy');
      final lrcFile = File(p.join(tempDir.path, 'track01.lrc'));
      await lrcFile.writeAsString('[00:10.00]Sidecar line');

      final found = LyricsExtractor.findSidecarFile(audioFile.path, '.lrc');
      expect(found, isNotNull);
      expect(found!.path, lrcFile.path);
    });

    test('finds sidecar with uppercase extension (.LRC)', () async {
      final audioFile = File(p.join(tempDir.path, 'song.flac'));
      await audioFile.writeAsString('audio dummy');
      final lrcFile = File(p.join(tempDir.path, 'song.LRC'));
      await lrcFile.writeAsString('[00:10.00]Uppercase ext');

      final found = LyricsExtractor.findSidecarFile(audioFile.path, '.lrc');
      expect(found, isNotNull);
    });

    test('finds sidecar .txt', () async {
      final audioFile = File(p.join(tempDir.path, 'song.mp3'));
      await audioFile.writeAsString('audio dummy');
      final txtFile = File(p.join(tempDir.path, 'song.txt'));
      await txtFile.writeAsString('Plain lyrics sidecar');

      final found = LyricsExtractor.findSidecarFile(audioFile.path, '.txt');
      expect(found, isNotNull);
      expect(found!.path, txtFile.path);
    });

    test('getSidecarMtime returns null when no sidecar exists', () async {
      final audioFile = File(p.join(tempDir.path, 'no_lyrics.mp3'));
      await audioFile.writeAsString('audio dummy');

      final mtime = LyricsExtractor.getSidecarMtime(audioFile.path);
      expect(mtime, isNull);
    });

    test('getSidecarMtime returns timestamp when sidecar exists', () async {
      final audioFile = File(p.join(tempDir.path, 'has_lyrics.mp3'));
      await audioFile.writeAsString('audio dummy');
      final lrcFile = File(p.join(tempDir.path, 'has_lyrics.lrc'));
      await lrcFile.writeAsString('[00:05.00]Lyrics');

      final mtime = LyricsExtractor.getSidecarMtime(audioFile.path);
      expect(mtime, isNotNull);
      expect(mtime, lrcFile.lastModifiedSync().millisecondsSinceEpoch);
    });
  });

  group('LyricsExtractor precedence and extraction', () {
    test('sidecar .lrc has highest precedence over .txt', () async {
      final audioFile = File(p.join(tempDir.path, 'track.mp3'));
      await audioFile.writeAsString('dummy mp3');
      final lrcFile = File(p.join(tempDir.path, 'track.lrc'));
      await lrcFile.writeAsString('[00:15.00]From LRC sidecar');
      final txtFile = File(p.join(tempDir.path, 'track.txt'));
      await txtFile.writeAsString('From TXT sidecar');

      final extractor = LyricsExtractor(
        processRunner: (cmd, args) async => ProcessResult(0, 1, '', ''),
      );

      final lyrics =
          await extractor.extractLyrics(audioFile.path, songId: 's1');
      expect(lyrics, isNotNull);
      expect(lyrics!.source, 'sidecar_lrc');
      expect(lyrics.type, LyricsType.synced);
      expect(lyrics.lines.first.text, 'From LRC sidecar');
    });

    test('falls back to sidecar .txt if no .lrc exists', () async {
      final audioFile = File(p.join(tempDir.path, 'track.mp3'));
      await audioFile.writeAsString('dummy mp3');
      final txtFile = File(p.join(tempDir.path, 'track.txt'));
      await txtFile.writeAsString('Plain line 1\nPlain line 2');

      final extractor = LyricsExtractor(
        processRunner: (cmd, args) async => ProcessResult(0, 1, '', ''),
      );

      final lyrics =
          await extractor.extractLyrics(audioFile.path, songId: 's1');
      expect(lyrics, isNotNull);
      expect(lyrics!.source, 'sidecar_txt');
      expect(lyrics.type, LyricsType.plain);
      expect(lyrics.lines.length, 2);
    });

    test('hasLyrics returns true when knownTags contains lyrics', () async {
      final audioFile = File(p.join(tempDir.path, 'track.flac'));
      await audioFile.writeAsString('dummy flac');

      final hasL = await LyricsExtractor.hasLyrics(
        audioFile.path,
        knownTags: {'lyrics': 'Some text'},
      );
      expect(hasL, isTrue);
    });

    test('hasLyrics is false for a tagless file without probing again',
        () async {
      final audioFile = File(p.join(tempDir.path, 'track.flac'));
      await audioFile.writeAsString('dummy flac');

      expect(
        await LyricsExtractor.hasLyrics(audioFile.path, knownTags: const {}),
        isFalse,
      );
    });
  });

  group('LyricsExtractor ID3v2 frames', () {
    Future<File> writeMp3(String name, List<List<int>> frames) async {
      final body = [for (final frame in frames) ...frame];
      final size = body.length;
      final file = File(p.join(tempDir.path, name));
      await file.writeAsBytes([
        ...'ID3'.codeUnits,
        3,
        0,
        0,
        (size >> 21) & 0x7F,
        (size >> 14) & 0x7F,
        (size >> 7) & 0x7F,
        size & 0x7F,
        ...body,
      ]);
      return file;
    }

    List<int> frame(String id, List<int> data) => [
          ...id.codeUnits,
          (data.length >> 24) & 0xFF,
          (data.length >> 16) & 0xFF,
          (data.length >> 8) & 0xFF,
          data.length & 0xFF,
          0,
          0,
          ...data,
        ];

    List<int> be32(int v) =>
        [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

    test('reads SYLT millisecond lyrics as synced LRC', () async {
      final file = await writeMp3('sylt.mp3', [
        frame('SYLT', [
          3, ...'eng'.codeUnits, 2, 1, 0, // utf8, ms stamps, empty descriptor
          ...'Second'.codeUnits, 0, ...be32(20000),
          ...'First'.codeUnits, 0, ...be32(10500),
        ]),
      ]);

      expect(await LyricsExtractor.hasLyrics(file.path), isTrue);
      final lyrics = await LyricsExtractor(externalToolsEnabled: false)
          .extractLyrics(file.path);
      expect(lyrics!.type, LyricsType.synced);
      expect(lyrics.lines.map((l) => l.text), ['First', 'Second']);
      expect(lyrics.lines.first.timestamp, const Duration(milliseconds: 10500));
      expect(lyrics.rawText, '[00:10.50]First\n[00:20.00]Second');
    });

    test('keeps line breaks in Latin-1 USLT lyrics', () async {
      final file = await writeMp3('uslt.mp3', [
        frame('USLT', [
          0, ...'eng'.codeUnits, 0, // latin1, empty descriptor
          ...latin1.encode('Line one\nLine two'),
        ]),
      ]);

      expect(await LyricsExtractor.hasLyrics(file.path), isTrue);
      final lyrics = await LyricsExtractor(externalToolsEnabled: false)
          .extractLyrics(file.path);
      expect(lyrics!.type, LyricsType.plain);
      expect(lyrics.lines.map((l) => l.text), ['Line one', 'Line two']);
    });
  });
}
