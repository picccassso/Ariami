part of 'package:ariami_core/services/transcoding/transcoding_service.dart';

extension _TranscodingServiceEnvironment on TranscodingService {
  /// Check if FFmpeg is available on the system.
  Future<bool> _isFFmpegAvailable() async {
    if (_ffmpegAvailable != null) return _ffmpegAvailable!;

    try {
      final result = await Process.run('ffmpeg', ['-version']);
      _ffmpegAvailable = result.exitCode == 0;
      if (_ffmpegAvailable!) {
        print('TranscodingService: FFmpeg is available');
      } else {
        print(
            'TranscodingService: FFmpeg not found (exit code ${result.exitCode})');
      }
    } catch (e) {
      print('TranscodingService: FFmpeg not available - $e');
      _ffmpegAvailable = false;
    }

    return _ffmpegAvailable!;
  }

  /// Check if ffprobe is available on the system.
  Future<bool> _isFFprobeAvailable() async {
    if (_ffprobeAvailable != null) return _ffprobeAvailable!;

    try {
      final result = await Process.run('ffprobe', ['-version']);
      _ffprobeAvailable = result.exitCode == 0;
    } catch (e) {
      _ffprobeAvailable = false;
    }

    return _ffprobeAvailable!;
  }

  /// Get audio properties using ffprobe.
  /// Returns null if ffprobe fails or file can't be analyzed.
  Future<_AudioProperties?> _getAudioProperties(String sourcePath) async {
    if (!await _isFFprobeAvailable()) return null;

    try {
      final result = await Process.run('ffprobe', [
        '-v',
        'quiet',
        '-select_streams',
        'a:0',
        '-show_entries',
        'stream=codec_name,bit_rate,sample_rate',
        '-of',
        'json',
        sourcePath,
      ]).timeout(const Duration(seconds: 5));

      if (result.exitCode != 0) return null;

      final json = jsonDecode(result.stdout as String);
      final streams = json['streams'] as List<dynamic>?;
      if (streams == null || streams.isEmpty) return null;

      final stream = streams[0] as Map<String, dynamic>;
      return _AudioProperties(
        codec: stream['codec_name'] as String?,
        bitrate: int.tryParse(stream['bit_rate']?.toString() ?? ''),
        sampleRate: int.tryParse(stream['sample_rate']?.toString() ?? ''),
      );
    } catch (e) {
      print('TranscodingService: ffprobe error - $e');
      return null;
    }
  }

  /// Detect and cache the best audio codec for this platform.
  ///
  /// On macOS, prefers `aac_at` (AudioToolbox hardware AAC) if available.
  /// Falls back to software `aac` on all other platforms or if detection fails.
  Future<String> _selectAudioCodec() async {
    if (_codecDetected) return _cachedAudioCodec!;

    _cachedAudioCodec = 'aac'; // Default fallback

    // Only check for hardware encoder on macOS
    if (Platform.isMacOS) {
      try {
        final result = await Process.run('ffmpeg', ['-encoders']);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          if (output.contains('aac_at')) {
            _cachedAudioCodec = 'aac_at';
            print(
                'TranscodingService: Using hardware AAC encoder (aac_at) on macOS');
          } else {
            print(
                'TranscodingService: Hardware AAC (aac_at) not available, using software AAC');
          }
        }
      } catch (e) {
        print(
            'TranscodingService: Codec detection failed, using software AAC - $e');
      }
    } else {
      print(
          'TranscodingService: Using software AAC encoder on ${Platform.operatingSystem}');
    }

    _codecDetected = true;
    return _cachedAudioCodec!;
  }

  /// Build FFmpeg arguments for transcoding.
  ///
  /// Uses platform-aware codec selection:
  /// - macOS: `aac_at` (AudioToolbox hardware AAC) if available
  /// - Other platforms: software `aac`
  Future<List<String>> _buildFFmpegArgs(
    String sourcePath,
    String outputPath,
    QualityPreset quality,
  ) async {
    final bitrate = quality.bitrate;
    if (bitrate == null) {
      throw ArgumentError('Cannot build FFmpeg args for high quality');
    }

    // Get platform-aware codec
    final codec = await _selectAudioCodec();

    return [
      '-y', // Overwrite output file without asking
      '-i', sourcePath, // Input file
      '-c:a', codec, // Audio codec: platform-aware AAC
      '-b:a', '${bitrate}k', // Bitrate
      '-vn', // No video
      '-movflags', '+faststart', // Enable streaming before full download
      '-map_metadata', '-1', // Strip metadata (smaller file, privacy)
      outputPath, // Output file
    ];
  }
}
