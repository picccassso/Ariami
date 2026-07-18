part of '../metadata_extractor.dart';

extension _MetadataExtractorMetadataPart on MetadataExtractor {
  /// Extracts metadata from a single audio file
  ///
  /// Returns [SongMetadata] with all available metadata extracted
  /// Falls back to filename parsing if metadata is missing or corrupted
  Future<SongMetadata> _extractMetadataImpl(String filePath) async {
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
        if (tagSize > fileSize ||
            tagSize > MetadataExtractor._maxTagSectionBytes) {
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
    if (value.length > MetadataExtractor._maxTagTextLength) {
      return 'oversized';
    }
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
  Future<SongMetadata> _extractMetadataWithDurationImpl(String filePath) async {
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
  Stream<List<SongMetadata>> _extractMetadataBatchImpl(
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
}
