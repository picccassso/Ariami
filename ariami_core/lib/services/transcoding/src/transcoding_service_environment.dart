part of 'package:ariami_core/services/transcoding/transcoding_service.dart';

extension _TranscodingServiceEnvironment on TranscodingService {
  /// Check if Sonic FFI library is available on this system.
  Future<bool> _isSonicAvailable() async {
    if (_sonicFfiAdapter != null) {
      return true;
    }

    for (final candidate in _buildSonicLibraryCandidates()) {
      final adapter = _SonicFfiAdapter.tryLoad(candidate);
      if (adapter != null) {
        _sonicFfiAdapter = adapter;
        print(
            'TranscodingService: Sonic FFI loaded from ${adapter.libraryPath}');
        return true;
      }
    }

    print(
        'TranscodingService: Sonic FFI library not found. Set ARIAMI_SONIC_LIB or pass sonicLibraryPath.');
    return false;
  }

  Iterable<String> _buildSonicLibraryCandidates() sync* {
    final seen = <String>{};

    // Dart doesn't allow yielding from nested function, so do inlined flow.
    String? explicit = sonicLibraryPath;
    if (explicit != null) {
      final trimmed = explicit.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        final file = File(trimmed);
        if (!trimmed.contains(Platform.pathSeparator) &&
            !trimmed.startsWith('.') &&
            !trimmed.startsWith('/')) {
          yield trimmed;
        } else if (file.existsSync()) {
          yield trimmed;
        }
      }
    }

    final fromEnv = Platform.environment['ARIAMI_SONIC_LIB'];
    if (fromEnv != null) {
      final trimmed = fromEnv.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        final file = File(trimmed);
        if (!trimmed.contains(Platform.pathSeparator) &&
            !trimmed.startsWith('.') &&
            !trimmed.startsWith('/')) {
          yield trimmed;
        } else if (file.existsSync()) {
          yield trimmed;
        }
      }
    }

    final libName = _platformSonicLibraryName();

    if (seen.add(libName)) {
      // Let OS loader search default paths/rpaths first.
      yield libName;
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final nearExecutable = <String>[
      p.join(exeDir, libName),
      p.join(exeDir, 'lib', libName),
      p.join(exeDir, '..', 'lib', libName),
      p.join(exeDir, '..', 'Frameworks', libName),
      p.join(exeDir, '..', '..', 'Frameworks', libName),
      p.join(exeDir, '..', '..', '..', 'Frameworks', libName),
    ];

    for (final candidate in nearExecutable) {
      if (!seen.add(candidate)) continue;
      if (File(candidate).existsSync()) {
        yield candidate;
      }
    }

    final cwd = Directory.current.path;
    final repoCandidates = <String>[
      p.join(cwd, 'sonic', 'target', 'release', libName),
      p.join(cwd, '..', 'sonic', 'target', 'release', libName),
      p.join(cwd, '..', '..', 'sonic', 'target', 'release', libName),
    ];
    for (final candidate in repoCandidates) {
      if (!seen.add(candidate)) continue;
      if (File(candidate).existsSync()) {
        yield candidate;
      }
    }
  }

  String _platformSonicLibraryName() {
    if (Platform.isMacOS) return 'libsonic_transcoder.dylib';
    if (Platform.isLinux) return 'libsonic_transcoder.so';
    if (Platform.isWindows) return 'sonic_transcoder.dll';
    return 'libsonic_transcoder.so';
  }

  int _sonicPresetForQuality(QualityPreset quality) {
    final adapter = _sonicFfiAdapter;
    if (adapter == null) {
      throw StateError('Sonic adapter is not loaded');
    }
    return adapter.presetForQuality(quality);
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
}
