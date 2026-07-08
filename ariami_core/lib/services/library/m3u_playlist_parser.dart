import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Result of parsing a single `.m3u` / `.m3u8` playlist file.
class M3uParseResult {
  const M3uParseResult({
    required this.entries,
    this.malformedReason,
  });

  /// Resolved, normalized absolute file paths in playlist order.
  /// Entries are NOT checked against the filesystem here — the caller
  /// matches them against the scanned library.
  final List<String> entries;

  /// Set when the file could not be read/decoded at all. A malformed
  /// playlist never breaks the scan; it just produces no entries.
  final String? malformedReason;

  bool get isMalformed => malformedReason != null;
}

/// Parses M3U/M3U8 playlist files.
///
/// Supported:
/// - `#`-prefixed comment/metadata lines (`#EXTM3U`, `#EXTINF`, ...) are
///   ignored.
/// - Blank lines are ignored.
/// - Absolute entries are kept as-is; relative entries resolve against the
///   playlist file's own directory.
/// - `file://` URIs are decoded to plain paths.
/// - Windows-style backslash separators are normalized on POSIX platforms.
/// - Content is decoded as UTF-8 with malformed bytes replaced, so legacy
///   Latin-1 files still parse (non-ASCII entries may not resolve).
///
/// Not supported (ignored safely): stream URLs (`http://`...), which are
/// skipped because Ariami playlists can only reference scanned local files.
class M3uPlaylistParser {
  const M3uPlaylistParser();

  static const supportedExtensions = ['.m3u', '.m3u8'];

  /// Whether [filePath] looks like an M3U playlist.
  static bool isM3uFile(String filePath) {
    return supportedExtensions
        .contains(path.extension(filePath).toLowerCase());
  }

  /// Reads and parses the playlist at [m3uPath].
  Future<M3uParseResult> parseFile(String m3uPath) async {
    List<int> bytes;
    try {
      bytes = await File(m3uPath).readAsBytes();
    } catch (e) {
      return M3uParseResult(
        entries: const [],
        malformedReason: 'could not read playlist file: $e',
      );
    }
    return parseContent(
      utf8.decode(bytes, allowMalformed: true),
      baseDirectory: path.dirname(m3uPath),
    );
  }

  /// Parses playlist [content], resolving relative entries against
  /// [baseDirectory].
  M3uParseResult parseContent(
    String content, {
    required String baseDirectory,
  }) {
    final entries = <String>[];

    for (var line in const LineSplitter().convert(content)) {
      line = line.trim();
      if (line.isEmpty) continue;
      // Strip a UTF-8 BOM that survives on the first line.
      if (line.startsWith('﻿')) {
        line = line.substring(1).trim();
        if (line.isEmpty) continue;
      }
      if (line.startsWith('#')) continue;

      final resolved = _resolveEntry(line, baseDirectory);
      if (resolved != null) {
        entries.add(resolved);
      }
    }

    return M3uParseResult(entries: entries);
  }

  String? _resolveEntry(String rawEntry, String baseDirectory) {
    var entry = rawEntry;

    final uri = Uri.tryParse(entry);
    if (uri != null && uri.hasScheme) {
      if (uri.isScheme('file')) {
        try {
          entry = uri.toFilePath();
        } catch (_) {
          return null;
        }
      } else if (uri.scheme.length > 1) {
        // Real scheme (http, https, ...): streams are not local files.
        // Single-letter "schemes" fall through — they are Windows drive
        // letters (C:\...), not URIs.
        return null;
      }
    }

    // Normalize Windows-style separators when scanning on POSIX systems.
    if (path.separator == '/' && entry.contains(r'\')) {
      entry = entry.replaceAll(r'\', '/');
    }

    if (path.isAbsolute(entry)) {
      return path.normalize(entry);
    }
    return path.normalize(path.join(baseDirectory, entry));
  }
}
