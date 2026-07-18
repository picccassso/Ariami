part of '../metadata_extractor.dart';

extension _MetadataExtractorProbesPart on MetadataExtractor {
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
      if (stdout.length > MetadataExtractor._maxTagSectionBytes) {
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
  Future<int?> _extractDurationImpl(String filePath) async {
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
}
