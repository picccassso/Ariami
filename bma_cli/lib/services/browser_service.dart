import 'dart:io';

/// Service for launching the web browser
class BrowserService {
  // Singleton pattern
  static final BrowserService _instance = BrowserService._internal();
  factory BrowserService() => _instance;
  BrowserService._internal();

  /// Open URL in default browser
  Future<bool> openUrl(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', url]);
      } else {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Open the BMA web interface
  Future<bool> openBmaInterface({String? tailscaleIp, int port = 8080}) async {
    final url = tailscaleIp != null
        ? 'http://$tailscaleIp:$port'
        : 'http://localhost:$port';

    return await openUrl(url);
  }
}
