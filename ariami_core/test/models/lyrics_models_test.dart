import 'package:ariami_core/models/lyrics_models.dart';
import 'package:test/test.dart';

void main() {
  group('LyricsLine', () {
    test('toJson and fromJson roundtrip', () {
      final line = LyricsLine(
        timestamp: const Duration(seconds: 42, milliseconds: 500),
        text: 'Hello world',
      );
      final json = line.toJson();
      expect(json['timestampMs'], 42500);
      expect(json['text'], 'Hello world');

      final reconstructed = LyricsLine.fromJson(json);
      expect(reconstructed.timestamp, line.timestamp);
      expect(reconstructed.text, line.text);
      expect(reconstructed, equals(line));
    });
  });

  group('LrcParser', () {
    test('parses standard LRC timestamps [mm:ss.xx]', () {
      const lrc = '''
[00:12.50]Line 1
[01:05.00]Line 2
[02:30.99]Line 3
''';
      final lyrics = LrcParser.parse(lrc, songId: 'song-1');
      expect(lyrics.type, LyricsType.synced);
      expect(lyrics.lines.length, 3);
      expect(lyrics.lines[0].timestamp, const Duration(seconds: 12, milliseconds: 500));
      expect(lyrics.lines[0].text, 'Line 1');
      expect(lyrics.lines[1].timestamp, const Duration(minutes: 1, seconds: 5));
      expect(lyrics.lines[1].text, 'Line 2');
      expect(lyrics.lines[2].timestamp, const Duration(minutes: 2, seconds: 30, milliseconds: 990));
      expect(lyrics.lines[2].text, 'Line 3');
    });

    test('parses 3-digit millisecond timestamps [mm:ss.xxx]', () {
      const lrc = '[00:05.123]Line with 3 digits';
      final lyrics = LrcParser.parse(lrc);
      expect(lyrics.type, LyricsType.synced);
      expect(lyrics.lines.first.timestamp, const Duration(seconds: 5, milliseconds: 123));
      expect(lyrics.lines.first.text, 'Line with 3 digits');
    });

    test('parses timestamps without fraction [mm:ss]', () {
      const lrc = '[00:45]Line without fraction';
      final lyrics = LrcParser.parse(lrc);
      expect(lyrics.type, LyricsType.synced);
      expect(lyrics.lines.first.timestamp, const Duration(seconds: 45));
    });

    test('handles repeated timestamps on single line [mm:ss.xx][mm:ss.xx]', () {
      const lrc = '[00:10.00][00:20.00]Chorus line';
      final lyrics = LrcParser.parse(lrc);
      expect(lyrics.type, LyricsType.synced);
      expect(lyrics.lines.length, 2);
      expect(lyrics.lines[0].timestamp, const Duration(seconds: 10));
      expect(lyrics.lines[0].text, 'Chorus line');
      expect(lyrics.lines[1].timestamp, const Duration(seconds: 20));
      expect(lyrics.lines[1].text, 'Chorus line');
    });

    test('applies positive and negative [offset: +/-ms]', () {
      const lrcPos = '''
[offset: 500]
[00:10.00]Positive offset
''';
      final lyricsPos = LrcParser.parse(lrcPos);
      expect(lyricsPos.lines.first.timestamp, const Duration(seconds: 9, milliseconds: 500));

      const lrcNeg = '''
[offset: -500]
[00:10.00]Negative offset
''';
      final lyricsNeg = LrcParser.parse(lrcNeg);
      expect(lyricsNeg.lines.first.timestamp, const Duration(seconds: 10, milliseconds: 500));
    });

    test('falls back to plain lyrics when no timestamps are present', () {
      const text = '''
[ti:Sample Title]
[ar:Sample Artist]

First verse line
Second verse line

Chorus line
''';
      final lyrics = LrcParser.parse(text);
      expect(lyrics.type, LyricsType.plain);
      expect(lyrics.lines.length, 4);
      expect(lyrics.lines[0].text, 'First verse line');
      expect(lyrics.lines[1].text, 'Second verse line');
      expect(lyrics.lines[2].text, '');
      expect(lyrics.lines[3].text, 'Chorus line');
    });
  });

  group('SongLyrics activeLineIndexAt', () {
    final lyrics = LrcParser.parse('''
[00:10.00]Line 0
[00:20.00]Line 1
[00:30.00]Line 2
''');

    test('returns -1 before the first timestamp', () {
      expect(lyrics.activeLineIndexAt(const Duration(seconds: 5)), -1);
      expect(lyrics.activeLineIndexAt(Duration.zero), -1);
    });

    test('returns correct index at exact boundaries', () {
      expect(lyrics.activeLineIndexAt(const Duration(seconds: 10)), 0);
      expect(lyrics.activeLineIndexAt(const Duration(seconds: 20)), 1);
      expect(lyrics.activeLineIndexAt(const Duration(seconds: 30)), 2);
    });

    test('returns correct index between boundaries', () {
      expect(lyrics.activeLineIndexAt(const Duration(seconds: 15)), 0);
      expect(lyrics.activeLineIndexAt(const Duration(seconds: 25)), 1);
    });

    test('returns last index for position beyond last timestamp', () {
      expect(lyrics.activeLineIndexAt(const Duration(minutes: 5)), 2);
    });

    test('handles empty lines list gracefully', () {
      const emptyLyrics = SongLyrics(
        songId: 'empty',
        type: LyricsType.synced,
        rawText: '',
        lines: [],
        source: 'test',
      );
      expect(emptyLyrics.activeLineIndexAt(const Duration(seconds: 10)), -1);
    });
  });

  group('SongLyrics serialization', () {
    test('toJson and fromJson roundtrip', () {
      final original = SongLyrics(
        songId: 'test-song-id',
        type: LyricsType.synced,
        rawText: '[00:10.00]Test',
        lines: [
          const LyricsLine(timestamp: Duration(seconds: 10), text: 'Test'),
        ],
        source: 'sidecar_lrc',
      );

      final json = original.toJson();
      final restored = SongLyrics.fromJson(json);

      expect(restored.songId, original.songId);
      expect(restored.type, original.type);
      expect(restored.rawText, original.rawText);
      expect(restored.lines.length, 1);
      expect(restored.lines.first.text, 'Test');
      expect(restored.source, original.source);
    });
  });
}
