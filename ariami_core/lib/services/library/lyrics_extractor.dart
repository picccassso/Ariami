import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../../models/lyrics_models.dart';
import '../../utils/mojibake_repair.dart';
import '../../utils/process_runner.dart';

/// Service for detecting and extracting lyrics from sidecar files and audio tags.
class LyricsExtractor {
  final ProcessRunner _processRunner;
  final Duration _processTimeout;
  final bool _externalToolsEnabled;

  LyricsExtractor({
    ProcessRunner? processRunner,
    Duration processTimeout = const Duration(seconds: 5),
    bool externalToolsEnabled = true,
  })  : _processRunner = processRunner ?? Process.run,
        _processTimeout = processTimeout,
        _externalToolsEnabled = externalToolsEnabled;

  static final RegExp _frameIdPattern = RegExp(r'^[A-Z0-9]{4}$');

  /// Scan-time check for whether a song has lyrics.
  ///
  /// Never spawns a process: MP3s are checked by walking their ID3v2 frames,
  /// other formats through the tags the metadata probe already read
  /// ([knownTags], lowercased ffprobe keys).
  static Future<bool> hasLyrics(String filePath,
      {Map<String, String>? knownTags}) async {
    try {
      if (findSidecarFile(filePath, '.lrc') != null ||
          findSidecarFile(filePath, '.txt') != null) {
        return true;
      }
      if (knownTags != null &&
          knownTags.entries.any((tag) =>
              _isLyricsTagKey(tag.key) && tag.value.trim().isNotEmpty)) {
        return true;
      }
      if (p.extension(filePath).toLowerCase() == '.mp3') {
        final id3 = await _readId3v2Lyrics(File(filePath), '');
        return id3.synced != null || id3.text != null;
      }
    } catch (_) {}
    return false;
  }

  /// Modification time (ms) of the sidecar lyrics file (.lrc, else .txt), or
  /// null when there is none.
  static int? getSidecarMtime(String filePath) {
    for (final ext in const ['.lrc', '.txt']) {
      final file = findSidecarFile(filePath, ext);
      if (file == null) continue;
      try {
        return file.lastModifiedSync().millisecondsSinceEpoch;
      } catch (_) {}
    }
    return null;
  }

  /// Full lazy extraction on demand following precedence:
  /// 1. Sidecar .lrc
  /// 2. Embedded synced lyrics (SYLT, or LRC-timestamped lyrics tags)
  /// 3. Sidecar .txt
  /// 4. Embedded plain lyrics
  Future<SongLyrics?> extractLyrics(
    String filePath, {
    String songId = '',
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      SongLyrics? parse(String? text, String source) {
        if (text == null || text.trim().isEmpty) return null;
        final parsed = LrcParser.parse(text, songId: songId, source: source);
        return parsed.lines.isEmpty ? null : parsed;
      }

      final lrc = parse(await _readSidecar(filePath, '.lrc'), 'sidecar_lrc');
      if (lrc != null) return lrc;

      String? embeddedText;
      if (p.extension(filePath).toLowerCase() == '.mp3') {
        final id3 = await _readId3v2Lyrics(file, songId);
        if (id3.synced != null) return id3.synced;
        embeddedText = id3.text;
      }
      if (embeddedText == null && _externalToolsEnabled) {
        embeddedText = await _probeLyricsWithFfprobe(filePath);
      }

      final embeddedSynced = parse(embeddedText, 'embedded_synced');
      if (embeddedSynced != null && embeddedSynced.isSynced) {
        return embeddedSynced;
      }

      return parse(await _readSidecar(filePath, '.txt'), 'sidecar_txt') ??
          parse(embeddedText, 'embedded_plain');
    } catch (_) {}
    return null;
  }

  /// Sidecar named `<audio basename><ext>`, matching the extension in lower
  /// or upper case. Deliberately no directory listing: this runs for every
  /// track on every scan, so it stays at a few stat calls.
  static File? findSidecarFile(String audioFilePath, String targetExt) {
    final ext = targetExt.startsWith('.')
        ? targetExt.toLowerCase()
        : '.${targetExt.toLowerCase()}';
    final base = p.withoutExtension(audioFilePath);
    for (final candidate in ['$base$ext', '$base${ext.toUpperCase()}']) {
      final file = File(candidate);
      if (file.existsSync()) return file;
    }
    return null;
  }

  static bool _isLyricsTagKey(String key) =>
      key.startsWith('lyrics') || key == 'unsyncedlyrics' || key == '©lyr';

  static Future<String?> _readSidecar(String audioFilePath, String ext) async {
    final file = findSidecarFile(audioFilePath, ext);
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return _decodeText(bytes, 0);
      }
    } catch (_) {
      return null;
    }
  }

  /// Reads the first non-empty USLT text and millisecond-synced SYLT frame
  /// from an MP3's ID3v2.3/2.4 tag.
  static Future<({SongLyrics? synced, String? text})> _readId3v2Lyrics(
    File file,
    String songId,
  ) async {
    SongLyrics? synced;
    String? text;
    final tag = await _readId3v2Tag(file);
    if (tag == null) return (synced: synced, text: text);

    final body = tag.body;
    var offset = 0;
    while (offset + 10 <= body.length && (synced == null || text == null)) {
      final frameId = String.fromCharCodes(body, offset, offset + 4);
      if (!_frameIdPattern.hasMatch(frameId)) break;

      final frameSize = tag.version == 4
          ? _syncSafeInt(body, offset + 4)
          : _bigEndianInt(body, offset + 4);
      final frameStart = offset + 10;
      final frameEnd = frameStart + frameSize;
      if (frameSize <= 0 || frameEnd > body.length) break;

      final frame = body.sublist(frameStart, frameEnd);
      if (frameId == 'USLT' && text == null) {
        final value = _parseUsltFrame(frame);
        if (value != null && value.trim().isNotEmpty) text = value;
      } else if (frameId == 'SYLT') {
        synced ??= _parseSyltFrame(frame, songId);
      }
      offset = frameEnd;
    }
    return (synced: synced, text: text);
  }

  static Future<({int version, List<int> body})?> _readId3v2Tag(
      File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final header = await raf.read(10);
      if (header.length != 10 ||
          header[0] != 0x49 ||
          header[1] != 0x44 ||
          header[2] != 0x33) {
        return null;
      }
      final version = header[3];
      if (version != 3 && version != 4) return null;
      final tagSize = _syncSafeInt(header, 6);
      if (tagSize <= 0 || tagSize > 16 * 1024 * 1024) return null;
      return (version: version, body: await raf.read(tagSize));
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  /// USLT: encoding, language(3), descriptor, text.
  static String? _parseUsltFrame(List<int> frame) {
    if (frame.length < 5) return null;
    final encoding = frame[0];
    final descEnd = _terminatorIndex(frame, 4, encoding);
    final textStart = descEnd < 0 ? 4 : descEnd + _terminatorWidth(encoding);
    if (textStart >= frame.length) return null;
    return _decodeText(frame.sublist(textStart), encoding);
  }

  /// SYLT: encoding, language(3), timestamp format, content type, descriptor,
  /// then (text, 32-bit timestamp) pairs. Only millisecond timestamps
  /// (format 2) map onto a playback position; MPEG-frame stamps are ignored.
  static SongLyrics? _parseSyltFrame(List<int> frame, String songId) {
    if (frame.length < 6 || frame[4] != 2) return null;
    final encoding = frame[0];
    final width = _terminatorWidth(encoding);
    final descEnd = _terminatorIndex(frame, 6, encoding);
    if (descEnd < 0) return null;

    final lines = <LyricsLine>[];
    var offset = descEnd + width;
    while (offset < frame.length) {
      final end = _terminatorIndex(frame, offset, encoding);
      if (end < 0 || end + width + 4 > frame.length) break;
      lines.add(LyricsLine(
        timestamp: Duration(milliseconds: _bigEndianInt(frame, end + width)),
        text: _decodeText(frame.sublist(offset, end), encoding).trim(),
      ));
      offset = end + width + 4;
    }
    if (lines.isEmpty) return null;

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return SongLyrics(
      songId: songId,
      type: LyricsType.synced,
      // Kept as LRC so clients can persist it as a companion .lrc file.
      rawText: lines
          .map((l) => '[${_lrcTimestamp(l.timestamp)}]${l.text}')
          .join('\n'),
      lines: lines,
      source: 'embedded_synced',
    );
  }

  static String _lrcTimestamp(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}'
        '.${two(d.inMilliseconds.remainder(1000) ~/ 10)}';
  }

  static int _terminatorWidth(int encoding) =>
      encoding == 1 || encoding == 2 ? 2 : 1;

  static int _terminatorIndex(List<int> bytes, int start, int encoding) {
    final width = _terminatorWidth(encoding);
    for (var i = start; i + width <= bytes.length; i += width) {
      if (bytes[i] == 0 && (width == 1 || bytes[i + 1] == 0)) return i;
    }
    return -1;
  }

  /// Decodes ID3 text by its encoding byte. Lyrics keep their line breaks, so
  /// this deliberately avoids the tag sanitizer (which strips control chars).
  static String _decodeText(List<int> bytes, int encoding) {
    switch (encoding) {
      case 0:
        final raw = latin1.decode(bytes);
        return (repairLatin1Mojibake(raw) ?? raw).replaceAll('\u0000', '');
      case 1:
      case 2:
        return _decodeUtf16(bytes, bigEndian: encoding == 2);
      default:
        return utf8
            .decode(bytes, allowMalformed: true)
            .replaceAll('\u0000', '');
    }
  }

  static String _decodeUtf16(List<int> bytes, {required bool bigEndian}) {
    var start = 0;
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        bigEndian = true;
        start = 2;
      } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        bigEndian = false;
        start = 2;
      }
    }
    final codeUnits = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      final unit = bigEndian
          ? (bytes[i] << 8) | bytes[i + 1]
          : (bytes[i + 1] << 8) | bytes[i];
      if (unit != 0) codeUnits.add(unit);
    }
    return String.fromCharCodes(codeUnits);
  }

  Future<String?> _probeLyricsWithFfprobe(String filePath) async {
    try {
      final result = await _processRunner('ffprobe', [
        '-v',
        'quiet',
        '-show_entries',
        'format_tags=lyrics,unsyncedlyrics:stream_tags=lyrics,unsyncedlyrics',
        '-of',
        'json',
        filePath,
      ]).timeout(_processTimeout);
      if (result.exitCode != 0 || result.stdout is! String) return null;

      final decoded = jsonDecode(result.stdout as String);
      if (decoded is! Map) return null;
      final streams = decoded['streams'];
      final tagMaps = [
        if (decoded['format'] is Map) (decoded['format'] as Map)['tags'],
        if (streams is List)
          for (final stream in streams)
            if (stream is Map) stream['tags'],
      ];
      for (final tags in tagMaps) {
        if (tags is! Map) continue;
        for (final entry in tags.entries) {
          final key = entry.key.toString().toLowerCase().trim();
          final value = entry.value?.toString().trim();
          if (_isLyricsTagKey(key) && value != null && value.isNotEmpty) {
            return value;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static int _syncSafeInt(List<int> bytes, int offset) {
    return ((bytes[offset] & 0x7F) << 21) |
        ((bytes[offset + 1] & 0x7F) << 14) |
        ((bytes[offset + 2] & 0x7F) << 7) |
        (bytes[offset + 3] & 0x7F);
  }

  static int _bigEndianInt(List<int> bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}
