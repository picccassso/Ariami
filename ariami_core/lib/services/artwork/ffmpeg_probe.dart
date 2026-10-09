import '../../utils/process_runner.dart';

typedef ArtworkProcessRunner = ProcessRunner;

/// Caches whether FFmpeg can be run through [run].
class FfmpegProbe {
  FfmpegProbe(this.run);

  /// Runs a process; injectable so tests never need a real FFmpeg.
  final ArtworkProcessRunner run;

  bool? _available;

  Future<bool> isAvailable() async {
    if (_available != null) return _available!;

    try {
      final result = await run('ffmpeg', ['-version']);
      _available = result.exitCode == 0;
      if (_available!) {
        print('[FfmpegProbe] FFmpeg is available');
      } else {
        print('[FfmpegProbe] FFmpeg not found (exit code ${result.exitCode})');
      }
    } catch (e) {
      print('[FfmpegProbe] FFmpeg not available - $e');
      _available = false;
    }

    return _available!;
  }
}
