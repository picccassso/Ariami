/// The type of lyrics representation.
enum LyricsType {
  /// Timestamp-synchronized lyrics (e.g. standard LRC).
  synced,

  /// Plain unsynchronized text lyrics.
  plain,
}

/// A single line of lyrics with its associated playback timestamp.
class LyricsLine {
  final Duration timestamp;
  final String text;

  const LyricsLine({
    required this.timestamp,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'timestampMs': timestamp.inMilliseconds,
        'text': text,
      };

  factory LyricsLine.fromJson(Map<String, dynamic> json) {
    return LyricsLine(
      timestamp:
          Duration(milliseconds: (json['timestampMs'] as num?)?.toInt() ?? 0),
      text: json['text'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsLine &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          text == other.text;

  @override
  int get hashCode => timestamp.hashCode ^ text.hashCode;

  @override
  String toString() => 'LyricsLine(timestamp: $timestamp, text: "$text")';
}

/// Full lyrics document for a song.
class SongLyrics {
  final String songId;
  final LyricsType type;
  final String rawText;
  final List<LyricsLine> lines;
  final String source;

  const SongLyrics({
    required this.songId,
    required this.type,
    required this.rawText,
    required this.lines,
    required this.source,
  });

  bool get isSynced => type == LyricsType.synced;
  bool get isPlain => type == LyricsType.plain;

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'type': type.name,
        'rawText': rawText,
        'lines': lines.map((l) => l.toJson()).toList(),
        'source': source,
      };

  factory SongLyrics.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    final type = LyricsType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => LyricsType.plain,
    );
    final linesList = (json['lines'] as List<dynamic>?)
            ?.map((e) => LyricsLine.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    return SongLyrics(
      songId: json['songId'] as String? ?? '',
      type: type,
      rawText: json['rawText'] as String? ?? '',
      lines: linesList,
      source: json['source'] as String? ?? 'unknown',
    );
  }

  /// Binary search helper to find the active line index at given position.
  /// If before the first line, returns -1.
  /// If after or at line i and before line i+1, returns i.
  int activeLineIndexAt(Duration position) =>
      LrcParser.activeLineIndexAt(lines, position);
}

/// Parser for LRC format and plain lyrics text.
class LrcParser {
  static final RegExp _tagRegex =
      RegExp(r'\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]');
  static final RegExp _offsetRegex =
      RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
  static final RegExp _metaRegex = RegExp(r'^\[[a-zA-Z]+:.*\]$');

  /// Parses [text] as either synchronized LRC or plain lyrics.
  static SongLyrics parse(
    String text, {
    String songId = '',
    String source = 'parsed',
  }) {
    int offsetMs = 0;
    final offsetMatch = _offsetRegex.firstMatch(text);
    if (offsetMatch != null) {
      offsetMs = int.tryParse(offsetMatch.group(1)!) ?? 0;
    }

    final rawLines = text.split(RegExp(r'\r?\n'));
    final parsedTimedLines = <LyricsLine>[];

    for (final rawLine in rawLines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final tagMatches = _tagRegex.allMatches(trimmed).toList();
      if (tagMatches.isEmpty) {
        continue;
      }

      final lastTagMatch = tagMatches.last;
      final lyricText = trimmed.substring(lastTagMatch.end).trim();

      for (final match in tagMatches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fractionStr = match.group(3);

        int millis = 0;
        if (fractionStr != null) {
          if (fractionStr.length == 1) {
            millis = int.parse(fractionStr) * 100;
          } else if (fractionStr.length == 2) {
            millis = int.parse(fractionStr) * 10;
          } else if (fractionStr.length == 3) {
            millis = int.parse(fractionStr);
          } else {
            millis = int.parse(fractionStr.substring(0, 3));
          }
        }

        // A positive LRC offset makes lyrics appear sooner.
        var totalMs = minutes * 60 * 1000 + seconds * 1000 + millis - offsetMs;
        if (totalMs < 0) totalMs = 0;

        parsedTimedLines.add(LyricsLine(
          timestamp: Duration(milliseconds: totalMs),
          text: lyricText,
        ));
      }
    }

    if (parsedTimedLines.isNotEmpty) {
      parsedTimedLines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return SongLyrics(
        songId: songId,
        type: LyricsType.synced,
        rawText: text,
        lines: parsedTimedLines,
        source: source,
      );
    }

    // Fallback to plain lyrics: filter out metadata tags like [ti:...], keep lines
    final plainLines = <LyricsLine>[];
    for (final rawLine in rawLines) {
      final trimmed = rawLine.trim();
      if (_metaRegex.hasMatch(trimmed)) continue;
      plainLines.add(LyricsLine(timestamp: Duration.zero, text: trimmed));
    }
    while (plainLines.isNotEmpty && plainLines.first.text.isEmpty) {
      plainLines.removeAt(0);
    }
    while (plainLines.isNotEmpty && plainLines.last.text.isEmpty) {
      plainLines.removeLast();
    }

    return SongLyrics(
      songId: songId,
      type: LyricsType.plain,
      rawText: text,
      lines: plainLines,
      source: source,
    );
  }

  /// Binary search helper to find the active line index at given position.
  static int activeLineIndexAt(List<LyricsLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    if (position < lines.first.timestamp) return -1;
    if (position >= lines.last.timestamp) return lines.length - 1;

    int low = 0;
    int high = lines.length - 1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final midTime = lines[mid].timestamp;

      if (midTime <= position) {
        if (mid == lines.length - 1 || lines[mid + 1].timestamp > position) {
          return mid;
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return -1;
  }
}
