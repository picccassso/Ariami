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

part 'metadata_extractor/metadata_extractor_artwork.part.dart';
part 'metadata_extractor/metadata_extractor_metadata.part.dart';
part 'metadata_extractor/metadata_extractor_probes.part.dart';

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
  Future<SongMetadata> extractMetadata(String filePath) =>
      _extractMetadataImpl(filePath);

  /// Extracts metadata and duration from a single audio file in one call.
  Future<SongMetadata> extractMetadataWithDuration(String filePath) =>
      _extractMetadataWithDurationImpl(filePath);

  /// Extracts metadata from multiple files in batches.
  Stream<List<SongMetadata>> extractMetadataBatch(
    List<String> filePaths, {
    int batchSize = 50,
  }) =>
      _extractMetadataBatchImpl(filePaths, batchSize: batchSize);

  /// Cache for ffprobe availability check
  bool? _ffprobeAvailable;

  /// Extract audio duration from file.
  Future<int?> extractDuration(String filePath) =>
      _extractDurationImpl(filePath);

  /// Cleanup method - no longer needed but kept for API compatibility
  Future<void> dispose() async {
    // No resources to clean up - duration extraction now uses fresh players
  }

  /// Cheap check for embedded cover art without reading image bytes.
  Future<bool> hasEmbeddedArtwork(String filePath) =>
      _hasEmbeddedArtworkImpl(filePath);

  /// Returns a sidecar artwork path in the album directory of [songFilePath].
  String? findSidecarArtworkForSong(String songFilePath) =>
      _findSidecarArtworkForSongImpl(songFilePath);

  /// Extracts album artwork from a single audio file (lazy extraction).
  Future<List<int>?> extractArtwork(String filePath) =>
      _extractArtworkImpl(filePath);
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
