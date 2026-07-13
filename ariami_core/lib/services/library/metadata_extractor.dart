import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:dart_tags/dart_tags.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/album_art_detection.dart';
import 'package:ariami_core/services/library/mp3_duration_parser.dart';
import 'package:ariami_core/utils/mojibake_repair.dart';
import 'package:ariami_core/utils/text_sanitizer.dart';

export 'package:ariami_core/utils/text_sanitizer.dart' show sanitizeTagText;

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef BinaryProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef MetadataDiagnosticLogger = void Function(String message);

const bool _externalMetadataToolsEnabledByBuild =
    !bool.fromEnvironment('ARIAMI_DISABLE_EXTERNAL_METADATA_TOOLS');

Future<ProcessResult> _runBinaryProcess(
  String executable,
  List<String> arguments,
) =>
    Process.run(
      executable,
      arguments,
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );

void _defaultMetadataDiagnosticLogger(String message) {
  developer.log(message, name: 'MetadataExtractor');
}

/// Service for extracting metadata from audio files
class MetadataExtractor {
  MetadataExtractor({
    TagProcessor? tagProcessor,
    Mp3DurationParser? mp3DurationParser,
    ProcessRunner? processRunner,
    BinaryProcessRunner? binaryProcessRunner,
    MetadataDiagnosticLogger? diagnosticLogger,
    bool externalToolsEnabled = _externalMetadataToolsEnabledByBuild,
    Duration tagReadTimeout = const Duration(seconds: 3),
    Duration processTimeout = const Duration(seconds: 5),
  })  : _tagProcessor = tagProcessor ?? TagProcessor(),
        _mp3DurationParser = mp3DurationParser ?? Mp3DurationParser(),
        _processRunner = processRunner ?? Process.run,
        _binaryProcessRunner = binaryProcessRunner ?? _runBinaryProcess,
        _diagnosticLogger =
            diagnosticLogger ?? _defaultMetadataDiagnosticLogger,
        _externalToolsEnabled = externalToolsEnabled,
        _tagReadTimeout = tagReadTimeout,
        _processTimeout = processTimeout;

  final TagProcessor _tagProcessor;
  final Mp3DurationParser _mp3DurationParser;
  final ProcessRunner _processRunner;
  final BinaryProcessRunner _binaryProcessRunner;
  final MetadataDiagnosticLogger _diagnosticLogger;
  final bool _externalToolsEnabled;
  final Duration _tagReadTimeout;
  final Duration _processTimeout;

  static const int _maxTagSectionBytes = 16 * 1024 * 1024;
  static const int _maxTagTextLength = 4096;
  static const int _maxArtworkBytes = 64 * 1024 * 1024;

  /// Extracts metadata from a single audio file
  ///
  /// Returns [SongMetadata] with all available metadata extracted
  /// Falls back to filename parsing if metadata is missing or corrupted
  Future<SongMetadata> extractMetadata(String filePath) async {
    try {
      final file = File(filePath);

      // Get file stats
      final fileStat = await file.stat();
      final fileSize = fileStat.size;
      final modifiedTime = fileStat.modified;

      // Read metadata using optimized tag reading (reads only tag sections, not entire file)
      final tags = await _readTagsOptimized(file, fileSize);

      // Extract metadata from tags. Source rank makes precedence independent
      // of parser iteration order: ID3v2 > unknown/other > legacy ID3v1.
      var titleSelection = const _SelectedText();
      var artistSelection = const _SelectedText();
      var albumSelection = const _SelectedText();
      var albumArtistSelection = const _SelectedText();
      var genreSelection = const _SelectedText();
      var yearSelection = const _SelectedInt();
      var trackSelection = const _SelectedInt();
      var discSelection = const _SelectedInt();
      final rejectedFields = <String>{};
      int? duration;
      int? bitrate;
      List<int>? albumArt;

      for (final tag in tags) {
        final tagMap = tag.tags;
        final sourceRank = _tagSourceRank(tag);

        final parsedTitle =
            _fixEncoding(_getTagValue(tagMap, ['title', 'TIT2']));
        titleSelection = _selectText(
          titleSelection,
          parsedTitle,
          sourceRank,
          field: 'title',
          rejectedFields: rejectedFields,
        );

        final parsedArtist =
            _fixEncoding(_getTagValue(tagMap, ['artist', 'artists', 'TPE1']));
        artistSelection = _selectText(
          artistSelection,
          parsedArtist,
          sourceRank,
          field: 'artist',
          rejectedFields: rejectedFields,
        );

        final parsedAlbum =
            _fixEncoding(_getTagValue(tagMap, ['album', 'TALB']));
        albumSelection = _selectText(
          albumSelection,
          parsedAlbum,
          sourceRank,
          field: 'album',
          rejectedFields: rejectedFields,
        );

        final parsedAlbumArtist = _fixEncoding(_getTagValue(tagMap, [
          'albumartist',
          'album_artist',
          'album artist',
          'TPE2',
        ]));
        albumArtistSelection = _selectText(
          albumArtistSelection,
          parsedAlbumArtist,
          sourceRank,
          field: 'album_artist',
          rejectedFields: rejectedFields,
        );

        final parsedGenre =
            _fixEncoding(_getTagValue(tagMap, ['genre', 'TCON']));
        genreSelection = _selectText(
          genreSelection,
          parsedGenre,
          sourceRank,
          field: 'genre',
          rejectedFields: rejectedFields,
        );

        final rawYear = _getTagValue(tagMap, ['year', 'TYER', 'TDRC']);
        if (rawYear != null) {
          final parsedYear = _parseYear(rawYear);
          if (parsedYear == null) {
            rejectedFields.add('date');
            _diagnose('field_rejected source=id3 field=date reason=invalid');
          }
          yearSelection = _selectInt(yearSelection, parsedYear, sourceRank);
        }

        final rawTrack = _getTagValue(tagMap, ['track', 'tracknumber', 'TRCK']);
        if (rawTrack != null) {
          final parsedTrack = _parsePosition(rawTrack);
          if (parsedTrack == null) {
            rejectedFields.add('track');
            _diagnose('field_rejected source=id3 field=track reason=invalid');
          }
          trackSelection = _selectInt(trackSelection, parsedTrack, sourceRank);
        }

        final rawDisc = _getTagValue(tagMap, ['disc', 'discnumber', 'TPOS']);
        if (rawDisc != null) {
          final parsedDisc = _parsePosition(rawDisc);
          if (parsedDisc == null) {
            rejectedFields.add('disc');
            _diagnose('field_rejected source=id3 field=disc reason=invalid');
          }
          discSelection = _selectInt(discSelection, parsedDisc, sourceRank);
        }

        // Skip duration and album art extraction during scan - done lazily on demand
      }

      String? title = titleSelection.value;
      String? artist = artistSelection.value;
      String? album = albumSelection.value;
      String? albumArtist = albumArtistSelection.value;
      String? genre = genreSelection.value;
      int? year = yearSelection.value;
      int? trackNumber = trackSelection.value;
      int? discNumber = discSelection.value;

      final extension = p.extension(filePath).toLowerCase();
      final shouldProbe = extension != '.mp3' ||
          _needsFallback(title, field: 'title') ||
          _needsFallback(artist, field: 'artist') ||
          _needsFallback(album, field: 'album') ||
          rejectedFields.isNotEmpty;
      if (rejectedFields.isNotEmpty) {
        _diagnose(
          'rejected_fields format=${_safeFormat(filePath)} '
          'fields=${_sortedFields(rejectedFields)}',
        );
      }

      // ffprobe is the cross-format parser and a per-field fallback for MP3
      // fields that the primary parser omitted or rejected.
      if (shouldProbe) {
        final probed = await _probeWithFfprobe(filePath);
        if (probed != null) {
          String? probe(List<String> keys) {
            for (final key in keys) {
              final value = probed.tags[key];
              if (value != null) return value;
            }
            return null;
          }

          final fallbackFields = <String>{};
          String? fallbackText(
            String field,
            String? current,
            List<String> keys,
          ) {
            if (!_needsFallback(current, field: field)) return current;
            final fallback = _fixEncoding(probe(keys));
            if (_needsFallback(fallback, field: field)) return current;
            fallbackFields.add(field);
            return fallback;
          }

          title = fallbackText('title', title, ['title']);
          artist = fallbackText('artist', artist, ['artist', 'artists']);
          album = fallbackText('album', album, ['album']);
          albumArtist = fallbackText(
              'album_artist', albumArtist, ['album_artist', 'albumartist']);
          genre = fallbackText('genre', genre, ['genre']);

          if (year == null) {
            year = _parseYear(probe(['date', 'year', 'originaldate']));
            if (year != null) fallbackFields.add('date');
          }

          if (trackNumber == null) {
            trackNumber = _parsePosition(probe(['track', 'tracknumber']));
            if (trackNumber != null) fallbackFields.add('track');
          }

          if (discNumber == null) {
            discNumber = _parsePosition(probe(['disc', 'discnumber']));
            if (discNumber != null) fallbackFields.add('disc');
          }

          duration ??= probed.durationSeconds;
          bitrate ??= probed.bitrateKbps;
          if (fallbackFields.isNotEmpty) {
            _diagnose(
              'ffprobe_fallback format=${_safeFormat(filePath)} '
              'fields=${_sortedFields(fallbackFields)}',
            );
          }
        }
      }

      bitrate ??= await _extractBitrate(filePath);

      // Fallback: infer track number from filename prefix when tag is missing.
      // Example: "01 - Song Title.mp3" => 1
      trackNumber ??= _inferTrackNumberFromFilename(filePath);

      // Create metadata object
      var songMetadata = SongMetadata(
        filePath: filePath,
        title: title,
        artist: artist,
        albumArtist: albumArtist,
        album: album,
        year: year,
        trackNumber: trackNumber,
        discNumber: discNumber,
        genre: genre,
        duration: duration,
        bitrate: bitrate,
        comment: null,
        albumArt: albumArt,
        fileSize: fileSize,
        modifiedTime: modifiedTime,
      );

      // If title is missing, try to parse from filename
      if (songMetadata.title == null || songMetadata.title!.isEmpty) {
        songMetadata = _parseFromFilename(songMetadata);
      }

      return songMetadata;
    } catch (e) {
      _diagnose(
        'metadata_parse_failed format=${_safeFormat(filePath)} '
        'error=${e.runtimeType}',
      );
      // If metadata extraction fails, create metadata from filename only
      final file = File(filePath);
      final fileStat = await file.stat();

      return _parseFromFilename(
        SongMetadata(
          filePath: filePath,
          fileSize: fileStat.size,
          modifiedTime: fileStat.modified,
        ),
      );
    }
  }

  /// Reads container/stream tags (plus duration and bitrate) via ffprobe for
  /// formats dart_tags can't parse (FLAC/Vorbis comments, MP4 atoms, etc).
  ///
  /// Returns lowercased tag keys, or null when ffprobe is unavailable, fails,
  /// or finds no tags. Format-level tags win over stream-level ones.
  Future<
      ({
        Map<String, String> tags,
        int? durationSeconds,
        int? bitrateKbps,
        bool hasAttachedPicture,
      })?> _probeWithFfprobe(String filePath) async {
    if (!await _isFFprobeAvailable()) return null;

    try {
      final result = await _processRunner('ffprobe', [
        '-v',
        'quiet',
        '-show_entries',
        'format_tags=title,artist,artists,album,album_artist,albumartist,genre,date,year,originaldate,track,tracknumber,disc,discnumber:'
            'stream_tags=title,artist,artists,album,album_artist,albumartist,genre,date,year,originaldate,track,tracknumber,disc,discnumber:'
            'format=duration,bit_rate:stream=bit_rate,codec_type,codec_name:'
            'stream_disposition=attached_pic',
        '-of',
        'json',
        filePath,
      ]).timeout(_processTimeout);
      if (result.exitCode != 0 || result.stdout is! String) return null;

      final stdout = result.stdout as String;
      if (stdout.length > _maxTagSectionBytes) {
        _diagnose('ffprobe_output_rejected format=${_safeFormat(filePath)}');
        return null;
      }

      final decoded = jsonDecode(stdout) as Map<String, dynamic>;

      final tags = <String, String>{};
      void collect(dynamic tagMap) {
        if (tagMap is! Map) return;
        for (final entry in tagMap.entries) {
          final key = entry.key.toString().toLowerCase().trim();
          final value = _fixEncoding(entry.value);
          if (key.isEmpty || value == null || value.isEmpty) continue;
          tags.putIfAbsent(key, () => value);
        }
      }

      int? durationSeconds;
      int? bitrateBps;
      var hasAttachedPicture = false;

      final format = decoded['format'];
      if (format is Map) {
        collect(format['tags']);
        final durationValue = double.tryParse('${format['duration'] ?? ''}');
        if (durationValue != null && durationValue > 0) {
          durationSeconds = durationValue.round();
        }
        bitrateBps = int.tryParse('${format['bit_rate'] ?? ''}');
      }

      final streams = decoded['streams'];
      if (streams is List) {
        for (final stream in streams) {
          if (stream is Map) {
            collect(stream['tags']);
            bitrateBps ??= int.tryParse('${stream['bit_rate'] ?? ''}');
            final disposition = stream['disposition'];
            if (disposition is Map &&
                ('${disposition['attached_pic'] ?? '0'}' == '1' ||
                    disposition['attached_pic'] == true)) {
              hasAttachedPicture = true;
            }
          }
        }
      }

      return (
        tags: tags,
        durationSeconds: durationSeconds,
        bitrateKbps: (bitrateBps != null && bitrateBps > 0)
            ? (bitrateBps / 1000).round()
            : null,
        hasAttachedPicture: hasAttachedPicture,
      );
    } catch (e) {
      _diagnose(
        'ffprobe_failed format=${_safeFormat(filePath)} '
        'error=${e.runtimeType}',
      );
      return null;
    }
  }

  Future<int?> _extractBitrate(String filePath) async {
    final extension = p.extension(filePath).toLowerCase();
    if (extension == '.mp3') {
      return _mp3DurationParser.getBitrate(filePath);
    }
    if (!_externalToolsEnabled) return null;

    try {
      final result = await _processRunner('ffprobe', [
        '-v',
        'quiet',
        '-select_streams',
        'a:0',
        '-show_entries',
        'stream=bit_rate',
        '-of',
        'json',
        filePath,
      ]).timeout(_processTimeout);
      if (result.exitCode != 0) return null;

      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final streams = decoded['streams'] as List<dynamic>?;
      if (streams == null || streams.isEmpty) return null;
      final stream = streams.first as Map<String, dynamic>;
      final bitRateBps = int.tryParse(stream['bit_rate']?.toString() ?? '');
      if (bitRateBps == null || bitRateBps <= 0) return null;
      return (bitRateBps / 1000).round();
    } catch (_) {
      return null;
    }
  }

  /// Helper to get tag value by trying multiple key names
  dynamic _getTagValue(Map<String, dynamic> tagMap, List<String> keys) {
    for (final key in keys) {
      if (tagMap.containsKey(key)) {
        return tagMap[key];
      }
    }
    final lowerKeys = keys.map((key) => key.toLowerCase()).toSet();
    for (final entry in tagMap.entries) {
      if (lowerKeys.contains(entry.key.toLowerCase())) return entry.value;
    }
    return null;
  }

  /// Reads only the tag sections of an audio file instead of the entire file
  ///
  /// For MP3: reads only the bounded ID3v2 section and ID3v1 tail. Other
  /// formats bypass dart_tags and use ffprobe, avoiding unsafe full-file reads.
  Future<List<Tag>> _readTagsOptimized(File file, int fileSize) async {
    if (p.extension(file.path).toLowerCase() != '.mp3') return const <Tag>[];

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final header = await raf.read(10);
      List<int> tagBytes = header;

      final hasId3v2 = header.length == 10 &&
          header[0] == 0x49 &&
          header[1] == 0x44 &&
          header[2] == 0x33;
      if (hasId3v2) {
        final tagSize = 10 + _syncSafeInt(header, 6);
        if (tagSize > fileSize || tagSize > _maxTagSectionBytes) {
          tagBytes = const <int>[];
          _diagnose('id3_size_rejected format=.mp3');
        } else {
          await raf.setPosition(0);
          tagBytes = await raf.read(tagSize);
        }
      }

      Uint8List? id3v1Bytes;
      if (fileSize >= 128) {
        await raf.setPosition(fileSize - 128);
        final tail = await raf.read(128);
        if (tail.length == 128 &&
            tail[0] == 0x54 &&
            tail[1] == 0x41 &&
            tail[2] == 0x47) {
          id3v1Bytes = tail;
        }
      }

      final Uint8List allBytes;
      if (id3v1Bytes != null) {
        allBytes = Uint8List(tagBytes.length + id3v1Bytes.length);
        allBytes.setAll(0, tagBytes);
        allBytes.setAll(tagBytes.length, id3v1Bytes);
      } else {
        allBytes = Uint8List.fromList(tagBytes);
      }

      return await _tagProcessor
          .getTagsFromByteArray(Future.value(allBytes))
          .timeout(_tagReadTimeout);
    } catch (e) {
      _diagnose('dart_tags_failed format=.mp3 error=${e.runtimeType}');
      return const <Tag>[];
    } finally {
      await raf?.close();
    }
  }

  /// Fixes mojibake (UTF-8 bytes misread as Latin-1) and strips invisible
  /// control/format characters.
  ///
  /// Detects patterns like "Ã¡" (should be "á") or "Ð¢Ð°" (should be "Та") and
  /// repairs them. This happens when ID3 tags claim Latin-1 encoding but contain
  /// UTF-8 bytes — most notably legacy ID3v1 fields, which are fixed-width and
  /// frequently truncate UTF-8 text mid-character. See [repairLatin1Mojibake],
  /// which tolerates that truncation so the raw mojibake doesn't leak through.
  ///
  /// Always runs [sanitizeTagText] so NUL-padded ID3v1 fields don't leak
  /// terminators into stored metadata.
  String? _fixEncoding(dynamic value) {
    if (value == null) return null;
    var str = value is Iterable && value is! String
        ? value.map((item) => item.toString()).join('; ')
        : value.toString();
    if (str.isEmpty) return str;

    final nulParts = str
        .split('\u0000')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (nulParts.length > 1) str = nulParts.join('; ');

    final repaired = repairLatin1Mojibake(str);
    if (repaired != null) {
      str = repaired;
    }

    return sanitizeTagText(str);
  }

  int _tagSourceRank(Tag tag) {
    final version = (tag.version ?? '').toLowerCase().replaceFirst('v', '');
    if (version.startsWith('2.')) return 300;
    if (version.startsWith('1.')) return 100;
    return 200;
  }

  _SelectedText _selectText(
    _SelectedText current,
    String? candidate,
    int sourceRank, {
    required String field,
    required Set<String> rejectedFields,
  }) {
    if (candidate == null || candidate.isEmpty) return current;
    final reason = _suspicionReason(candidate, field: field);
    if (reason != null) {
      rejectedFields.add(field);
      _diagnose('field_rejected source=id3 field=$field reason=$reason');
      return current;
    }
    if (current.value == null || sourceRank > current.sourceRank) {
      return _SelectedText(value: candidate, sourceRank: sourceRank);
    }
    return current;
  }

  _SelectedInt _selectInt(
    _SelectedInt current,
    int? candidate,
    int sourceRank,
  ) {
    if (candidate == null) return current;
    if (current.value == null || sourceRank > current.sourceRank) {
      return _SelectedInt(value: candidate, sourceRank: sourceRank);
    }
    return current;
  }

  bool _needsFallback(String? value, {required String field}) =>
      value == null ||
      value.isEmpty ||
      _suspicionReason(value, field: field) != null;

  String? _suspicionReason(String value, {required String field}) {
    if (value.length > _maxTagTextLength) return 'oversized';
    if (value.contains('\uFFFD')) return 'replacement_character';

    final visible = value.replaceAll(RegExp(r'\s'), '');
    if (visible.isEmpty) return 'empty';
    final questionMarks = '?'.allMatches(visible).length;
    if (questionMarks >= 2 && questionMarks * 2 >= visible.length) {
      return 'question_mark_placeholder';
    }

    final lower = value.trim().toLowerCase();
    const genericPlaceholders = {
      '<unknown>',
      '[unknown]',
      '(unknown)',
      '<null>',
      'n/a',
    };
    if (genericPlaceholders.contains(lower)) return 'placeholder';
    if ((field == 'artist' || field == 'album_artist') &&
        lower == 'unknown artist') {
      return 'placeholder';
    }
    if (field == 'album' && lower == 'unknown album') return 'placeholder';
    if (field == 'title' && lower == 'unknown title') return 'placeholder';
    return null;
  }

  int? _parseYear(dynamic value) {
    if (value == null) return null;
    final match = RegExp(r'(?<!\d)(\d{4})(?!\d)').firstMatch(value.toString());
    final parsed = match == null ? null : int.tryParse(match.group(1)!);
    return parsed != null && parsed >= 1000 && parsed <= 9999 ? parsed : null;
  }

  int? _parsePosition(dynamic value) {
    if (value == null) return null;
    final match = RegExp(
      r'^\s*(\d{1,6})(?:\s*(?:/|of)\s*(\d{1,6}))?',
      caseSensitive: false,
    ).firstMatch(value.toString());
    final parsed = match == null ? null : int.tryParse(match.group(1)!);
    final total =
        match?.group(2) == null ? null : int.tryParse(match!.group(2)!);
    if (parsed == null || parsed <= 0) return null;
    if (total != null && (total <= 0 || total < parsed)) return null;
    return parsed;
  }

  void _diagnose(String message) => _diagnosticLogger(message);

  String _safeFormat(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    return extension.isEmpty ? 'unknown' : extension;
  }

  String _sortedFields(Set<String> fields) {
    final sorted = fields.toList()..sort();
    return sorted.join(',');
  }

  /// Extracts metadata and duration from a single audio file in one call
  ///
  /// This is more efficient than calling extractMetadata and extractDuration
  /// separately as it reduces the number of method calls and allows for
  /// potential future optimizations like shared file reads.
  Future<SongMetadata> extractMetadataWithDuration(String filePath) async {
    var metadata = await extractMetadata(filePath);
    if (metadata.duration != null && metadata.duration! > 0) {
      // Already resolved (e.g. by the ffprobe tag fallback) — skip the
      // separate duration probe.
      return metadata;
    }
    final duration = await extractDuration(filePath);
    if (duration != null) {
      metadata = metadata.copyWith(duration: duration);
    }
    return metadata;
  }

  /// Extracts metadata from multiple files in batches
  ///
  /// Yields batches of [SongMetadata] as they are processed
  /// Batch size is configurable (default: 50)
  Stream<List<SongMetadata>> extractMetadataBatch(
    List<String> filePaths, {
    int batchSize = 50,
  }) async* {
    final batches = <List<String>>[];

    // Split into batches
    for (var i = 0; i < filePaths.length; i += batchSize) {
      final end =
          (i + batchSize < filePaths.length) ? i + batchSize : filePaths.length;
      batches.add(filePaths.sublist(i, end));
    }

    // Process each batch
    for (final batch in batches) {
      final metadataList = <SongMetadata>[];

      // Process files sequentially to handle errors gracefully
      for (final path in batch) {
        try {
          final metadata = await extractMetadata(path);
          metadataList.add(metadata);
        } catch (e) {
          // Skip files that can't be processed
          _diagnose(
            'batch_item_failed format=${_safeFormat(path)} '
            'error=${e.runtimeType}',
          );
        }
      }

      if (metadataList.isNotEmpty) {
        yield metadataList;
      }
    }
  }

  /// Parses song information from filename when metadata is missing
  ///
  /// Supports common patterns:
  /// - "01 - Artist - Song Title.mp3"
  /// - "Artist - Album - 01 - Title.mp3"
  /// - "01_Song_Title.mp3"
  /// - "Song Title.mp3"
  SongMetadata _parseFromFilename(SongMetadata metadata) {
    final fileName = _getFileNameWithoutExtension(metadata.filePath);

    // Try pattern: "01 - Artist - Song Title"
    var pattern1 = RegExp(r'^(\d+)\s*-\s*(.+?)\s*-\s*(.+)$');
    var match = pattern1.firstMatch(fileName);
    if (match != null) {
      return metadata.copyWith(
        trackNumber: int.tryParse(match.group(1)!),
        artist: match.group(2)!.trim(),
        title: match.group(3)!.trim(),
      );
    }

    // Try pattern: "Artist - Album - 01 - Title"
    var pattern2 = RegExp(r'^(.+?)\s*-\s*(.+?)\s*-\s*(\d+)\s*-\s*(.+)$');
    match = pattern2.firstMatch(fileName);
    if (match != null) {
      return metadata.copyWith(
        artist: match.group(1)!.trim(),
        album: match.group(2)!.trim(),
        trackNumber: int.tryParse(match.group(3)!),
        title: match.group(4)!.trim(),
      );
    }

    // Try pattern: "01_Song_Title" or "01 Song Title"
    var pattern3 = RegExp(r'^(\d+)[_\s]+(.+)$');
    match = pattern3.firstMatch(fileName);
    if (match != null) {
      return metadata.copyWith(
        trackNumber: int.tryParse(match.group(1)!),
        title: match.group(2)!.trim().replaceAll('_', ' '),
      );
    }

    // Default: use filename as title
    return metadata.copyWith(title: fileName.replaceAll('_', ' '));
  }

  /// Gets the filename without extension
  String _getFileNameWithoutExtension(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) {
      return fileName;
    }
    return fileName.substring(0, lastDot);
  }

  /// Attempts to infer track number from filename prefixes like:
  /// "01 - Title", "1. Title", "07_Title", "12 Title".
  int? _inferTrackNumberFromFilename(String filePath) {
    final fileName = p.basenameWithoutExtension(filePath).trim();
    final match =
        RegExp(r'^(\d{1,3})(?:\s*[-._)]\s*|\s+)').firstMatch(fileName);
    if (match == null) return null;

    final parsed = int.tryParse(match.group(1)!);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  /// Cache for ffprobe availability check
  bool? _ffprobeAvailable;

  /// Check if ffprobe is available on the system
  Future<bool> _isFFprobeAvailable() async {
    if (!_externalToolsEnabled) return false;
    if (_ffprobeAvailable != null) return _ffprobeAvailable!;

    try {
      final result = await _processRunner('ffprobe', ['-version'])
          .timeout(_processTimeout);
      _ffprobeAvailable = result.exitCode == 0;
    } catch (_) {
      _ffprobeAvailable = false;
    }

    return _ffprobeAvailable!;
  }

  /// Extract audio duration from file
  ///
  /// Uses the in-process MP3 parser first for `.mp3` files to avoid
  /// expensive process spawning, and falls back to ffprobe when needed.
  Future<int?> extractDuration(String filePath) async {
    final extension = filePath.split('.').last.toLowerCase();

    if (extension == 'mp3') {
      try {
        final duration = await _mp3DurationParser.getDuration(filePath);
        if (duration != null && duration > 0) {
          return duration;
        }
      } catch (e) {
        // Parser failed, fall back to ffprobe below.
      }
    }

    // Use ffprobe for non-MP3 formats and as a fallback for MP3s the parser
    // cannot resolve reliably.
    if (await _isFFprobeAvailable()) {
      final duration = await _extractDurationWithFfprobe(filePath);
      if (duration != null && duration > 0) {
        return duration;
      }
    }

    return null;
  }

  Future<int?> _extractDurationWithFfprobe(String filePath) async {
    try {
      final result = await _processRunner('ffprobe', [
        '-v',
        'quiet',
        '-show_entries',
        'format=duration',
        '-of',
        'json',
        filePath,
      ]).timeout(_processTimeout);

      if (result.exitCode == 0) {
        final json = jsonDecode(result.stdout as String);
        final format = json['format'] as Map<String, dynamic>?;
        if (format != null) {
          final durationStr = format['duration']?.toString();
          if (durationStr != null) {
            final durationSeconds = double.tryParse(durationStr);
            if (durationSeconds != null) {
              return durationSeconds.round();
            }
          }
        }
      }
    } catch (e) {
      _diagnose(
        'duration_probe_failed format=${_safeFormat(filePath)} '
        'error=${e.runtimeType}',
      );
    }

    return null;
  }

  /// Cleanup method - no longer needed but kept for API compatibility
  Future<void> dispose() async {
    // No resources to clean up - duration extraction now uses fresh players
  }

  /// Cheap check for embedded cover art without reading image bytes.
  Future<bool> hasEmbeddedArtwork(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final extension = p.extension(filePath).toLowerCase();
      final fileStat = await file.stat();
      final tags = await _readTagsOptimized(file, fileStat.size);
      if (_extractArtworkFromTags(tags) != null) return true;

      if (extension == '.mp3') {
        if (await _readId3v2Artwork(file, extractBytes: false) != null) {
          return true;
        }
      }

      final probed = await _probeWithFfprobe(filePath);
      return probed?.hasAttachedPicture ?? false;
    } catch (e) {
      _diagnose(
        'artwork_detection_failed format=${_safeFormat(filePath)} '
        'error=${e.runtimeType}',
      );
      return false;
    }
  }

  /// Returns a sidecar artwork path in the album directory of [songFilePath].
  String? findSidecarArtworkForSong(String songFilePath) {
    final albumDir = p.dirname(songFilePath);
    return findAlbumSidecarArtworkPath(albumDir);
  }

  /// Extracts album artwork from a single audio file (lazy extraction)
  ///
  /// This is called on-demand when artwork is requested, not during scan.
  /// Returns the artwork bytes or null if no artwork found.
  Future<List<int>?> extractArtwork(String filePath) async {
    try {
      final file = File(filePath);
      final fileStat = await file.stat();
      final fileSize = fileStat.size;
      final extension = p.extension(filePath).toLowerCase();

      final optimizedTags = await _readTagsOptimized(file, fileSize);
      final parsedArtwork = _extractArtworkFromTags(optimizedTags);
      if (parsedArtwork != null) return parsedArtwork;

      if (extension == '.mp3') {
        final rawArtwork = await _readId3v2Artwork(file, extractBytes: true);
        if (rawArtwork != null) {
          _diagnose('artwork_raw_id3_fallback format=.mp3');
          return rawArtwork;
        }
      }

      final probed = await _probeWithFfprobe(filePath);
      if (probed?.hasAttachedPicture ?? false) {
        final artwork = await _extractArtworkWithFfmpeg(filePath);
        if (artwork != null) {
          _diagnose('artwork_ffmpeg_fallback format=${_safeFormat(filePath)}');
          return artwork;
        }
      }
      return null;
    } catch (e) {
      _diagnose(
        'artwork_extract_failed format=${_safeFormat(filePath)} '
        'error=${e.runtimeType}',
      );
      return null;
    }
  }

  List<int>? _extractArtworkFromTags(List<Tag> tags) {
    for (final tag in tags) {
      final tagMap = tag.tags;
      final picture = _getTagValue(tagMap, [
        'picture',
        'APIC',
        'PIC',
        'METADATA_BLOCK_PICTURE',
      ]);

      if (picture != null) {
        final direct = _coerceArtworkBytes(picture);
        if (direct != null) return direct;

        if (picture is Map) {
          final entries = picture.entries.toList()
            ..sort((a, b) {
              final aFront = a.key.toString().toLowerCase().contains('front');
              final bFront = b.key.toString().toLowerCase().contains('front');
              if (aFront == bFront) return 0;
              return aFront ? -1 : 1;
            });
          for (final entry in entries) {
            final bytes = _coerceArtworkBytes(entry.value);
            if (bytes != null) return bytes;

            try {
              final dynamic attachedPicture = entry.value;
              final attachedBytes =
                  _coerceArtworkBytes(attachedPicture.imageData);
              if (attachedBytes != null) return attachedBytes;
            } catch (_) {
              // Try the next picture entry or the external fallback.
            }
          }
        }
      }
    }
    return null;
  }

  List<int>? _coerceArtworkBytes(dynamic value) {
    if (value is Uint8List) return _validatedArtwork(value);
    if (value is List && value.every((element) => element is int)) {
      return _validatedArtwork(value.cast<int>());
    }
    return null;
  }

  Future<List<int>?> _extractArtworkWithFfmpeg(String filePath) async {
    if (!_externalToolsEnabled) return null;
    try {
      final result = await _binaryProcessRunner('ffmpeg', [
        '-v',
        'error',
        '-i',
        filePath,
        '-map',
        '0:v:0',
        '-frames:v',
        '1',
        '-c:v',
        'copy',
        '-f',
        'image2pipe',
        'pipe:1',
      ]).timeout(_processTimeout);
      if (result.exitCode != 0) return null;
      final stdout = result.stdout;
      if (stdout is Uint8List) return _validatedArtwork(stdout);
      if (stdout is List<int>) return _validatedArtwork(stdout);
    } catch (e) {
      _diagnose(
        'ffmpeg_artwork_failed format=${_safeFormat(filePath)} '
        'error=${e.runtimeType}',
      );
    }
    return null;
  }

  List<int>? _validatedArtwork(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > _maxArtworkBytes) return null;
    const jpeg = [0xFF, 0xD8];
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (!_startsWithBytes(bytes, jpeg, 0) && !_startsWithBytes(bytes, png, 0)) {
      return null;
    }
    return List<int>.from(bytes);
  }

  /// Reads a valid ID3v2 APIC frame directly when dart_tags omits it. This is
  /// bounded to the declared tag section and supports v2.3/v2.4 frame sizes.
  /// In detection mode an empty list is returned once valid image bytes are
  /// found, avoiding a second copy of the full cover.
  Future<List<int>?> _readId3v2Artwork(
    File file, {
    required bool extractBytes,
  }) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final header = await raf.read(10);
      if (header.length != 10 ||
          header[0] != 0x49 ||
          header[1] != 0x44 ||
          header[2] != 0x33) {
        return null;
      }

      final majorVersion = header[3];
      if (majorVersion != 3 && majorVersion != 4) return null;

      final tagSize = _syncSafeInt(header, 6);
      final fileSize = await file.length();
      if (tagSize <= 0 ||
          tagSize > fileSize - 10 ||
          tagSize > _maxTagSectionBytes) {
        return null;
      }

      await raf.setPosition(10);
      final body = await raf.read(tagSize);
      var offset = 0;

      var frameCount = 0;
      while (offset + 10 <= body.length && frameCount++ < 10000) {
        final frameId = String.fromCharCodes(body.sublist(offset, offset + 4));
        if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(frameId)) break;

        final frameSize = majorVersion == 4
            ? _syncSafeInt(body, offset + 4)
            : _bigEndianInt(body, offset + 4);
        final frameStart = offset + 10;
        final frameEnd = frameStart + frameSize;
        if (frameSize <= 0 || frameEnd > body.length) break;

        if (frameId == 'APIC') {
          final image = _extractApicBytes(
            body.sublist(frameStart, frameEnd),
            extractBytes: extractBytes,
          );
          if (image != null) return image;
        }

        offset = frameEnd;
      }
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
    return null;
  }

  List<int>? _extractApicBytes(
    List<int> frame, {
    required bool extractBytes,
  }) {
    if (frame.length < 5) return null;

    final mimeEnd = frame.indexOf(0, 1);
    if (mimeEnd < 0 || mimeEnd + 2 >= frame.length) return null;

    final encoding = frame[0];
    var imageStart = mimeEnd + 2;
    if (encoding == 1 || encoding == 2) {
      imageStart = _indexOfUtf16Terminator(frame, imageStart);
      if (imageStart < 0) return null;
      imageStart += 2;
    } else {
      imageStart = frame.indexOf(0, imageStart);
      if (imageStart < 0) return null;
      imageStart += 1;
    }

    const jpeg = [0xFF, 0xD8];
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (!_startsWithBytes(frame, jpeg, imageStart) &&
        !_startsWithBytes(frame, png, imageStart)) {
      return null;
    }

    final image = _validatedArtwork(frame.sublist(imageStart));
    if (image == null) return null;
    return extractBytes ? image : const <int>[];
  }

  int _syncSafeInt(List<int> bytes, int offset) =>
      ((bytes[offset] & 0x7F) << 21) |
      ((bytes[offset + 1] & 0x7F) << 14) |
      ((bytes[offset + 2] & 0x7F) << 7) |
      (bytes[offset + 3] & 0x7F);

  int _bigEndianInt(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  int _indexOfUtf16Terminator(List<int> bytes, int start) {
    for (var i = start; i + 1 < bytes.length; i += 2) {
      if (bytes[i] == 0 && bytes[i + 1] == 0) return i;
    }
    return -1;
  }

  bool _startsWithBytes(List<int> bytes, List<int> pattern, int offset) {
    if (offset < 0 || offset + pattern.length > bytes.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[offset + i] != pattern[i]) return false;
    }
    return true;
  }
}

class _SelectedText {
  const _SelectedText({this.value, this.sourceRank = -1});

  final String? value;
  final int sourceRank;
}

class _SelectedInt {
  const _SelectedInt({this.value, this.sourceRank = -1});

  final int? value;
  final int sourceRank;
}
