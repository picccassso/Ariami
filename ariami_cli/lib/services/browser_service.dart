import 'dart:io';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef HasDisplaySession = bool Function();

/// Service for launching the web browser
class BrowserService {
  BrowserService._({
    ProcessRunner? processRunner,
    HasDisplaySession? hasDisplaySession,
  })  : _processRunner = processRunner ?? Process.run,
        _hasDisplaySession = hasDisplaySession ?? _defaultHasDisplaySession;

  factory BrowserService({
    ProcessRunner? processRunner,
    HasDisplaySession? hasDisplaySession,
  }) {
    if (processRunner != null || hasDisplaySession != null) {
      return BrowserService._(
        processRunner: processRunner,
        hasDisplaySession:
            processRunner != null ? () => true : hasDisplaySession,
      );
    }
    return _defaultInstance ??= BrowserService._();
  }

  static BrowserService? _defaultInstance;

  final ProcessRunner _processRunner;
  final HasDisplaySession _hasDisplaySession;

  /// Open URL in default browser
  Future<bool> openUrl(String url) async {
    try {
      if (Platform.isLinux && !_hasDisplaySession()) {
        return false;
      }

      final ProcessResult result;
      if (Platform.isMacOS) {
        result = await _processRunner('open', [url]);
      } else if (Platform.isLinux) {
        result = await _processRunner('xdg-open', [url]);
      } else if (Platform.isWindows) {
        result = await _processRunner('cmd', ['/c', 'start', url]);
      } else {
        return false;
      }

      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Open the Ariami web interface
  Future<bool> openAriamiInterface(
      {String? tailscaleIp, int port = 8080}) async {
    final url = tailscaleIp != null
        ? 'http://$tailscaleIp:$port'
        : 'http://localhost:$port';

    return openUrl(url);
  }

  static bool _defaultHasDisplaySession() {
    final display = Platform.environment['DISPLAY'];
    final wayland = Platform.environment['WAYLAND_DISPLAY'];
    return (display != null && display.isNotEmpty) ||
        (wayland != null && wayland.isNotEmpty);
  }
}
