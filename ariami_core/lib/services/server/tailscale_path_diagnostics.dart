import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef TailscaleProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Periodically logs an identity-free summary of active Tailscale paths.
///
/// Ariami cannot observe DERP from its ordinary HTTP sockets. The local
/// Tailscale CLI is the authoritative source, so this sampler records only
/// aggregate direct/relay/idle counts and never peer names or addresses.
class TailscalePathDiagnostics {
  TailscalePathDiagnostics({
    TailscaleProcessRunner? processRunner,
    void Function(String message)? logger,
    this.interval = const Duration(minutes: 1),
  })  : _processRunner = processRunner ?? Process.run,
        _logger = logger ?? print;

  final TailscaleProcessRunner _processRunner;
  final void Function(String message) _logger;
  final Duration interval;
  Timer? _timer;
  bool _sampling = false;

  void start() {
    if (_timer != null) return;
    unawaited(sample());
    _timer = Timer.periodic(interval, (_) => unawaited(sample()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Known CLI locations, tried in order. On macOS, GUI processes don't get
  /// the user's shell PATH and the App Store / standalone Tailscale keeps its
  /// CLI inside the app bundle, so a bare `tailscale` usually fails there.
  static List<String> get _executableCandidates {
    if (Platform.isWindows) return const <String>['tailscale.exe'];
    if (Platform.isMacOS) {
      return const <String>[
        'tailscale',
        '/Applications/Tailscale.app/Contents/MacOS/Tailscale',
      ];
    }
    return const <String>['tailscale'];
  }

  Future<void> sample() async {
    if (_sampling) return;
    _sampling = true;
    try {
      ProcessResult? result;
      for (final executable in _executableCandidates) {
        try {
          result = await _processRunner(
            executable,
            const <String>['status', '--json'],
          ).timeout(const Duration(seconds: 4));
          break;
        } on ProcessException {
          // Not at this location; try the next candidate.
        }
      }
      if (result == null || result.exitCode != 0) return;
      final decoded = jsonDecode(result.stdout as String);
      if (decoded is! Map) return;
      final peers = decoded['Peer'];
      if (peers is! Map) return;

      var direct = 0;
      var relay = 0;
      var idle = 0;
      for (final rawPeer in peers.values) {
        if (rawPeer is! Map || rawPeer['Active'] != true) continue;
        final currentAddress = rawPeer['CurAddr'] as String? ?? '';
        final relayName = rawPeer['Relay'] as String? ?? '';
        if (currentAddress.isNotEmpty) {
          direct++;
        } else if (relayName.isNotEmpty) {
          relay++;
        } else {
          idle++;
        }
      }

      _logger('[TailscaleMetrics] ${jsonEncode(<String, dynamic>{
            'type': 'tailscale_path_summary',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'activeDirect': direct,
            'activeRelay': relay,
            'activeUnresolved': idle,
          })}');
    } catch (_) {
      // Tailscale and its CLI are optional. Diagnostics must never affect the
      // server lifecycle or emit noisy errors when unavailable.
    } finally {
      _sampling = false;
    }
  }
}
