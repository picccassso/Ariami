import 'dart:io';

/// Service for managing Tailscale detection and IP address resolution on CLI
class CliTailscaleService {
  /// Get the best IP address for mobile connections
  /// 
  /// Priority: Tailscale IP > LAN IP > localhost
  Future<String> getBestAdvertisedIp() async {
    // Try Tailscale first
    final tailscaleIp = await getTailscaleIp();
    if (tailscaleIp != null) {
      print('Using Tailscale IP: $tailscaleIp');
      return tailscaleIp;
    }

    // Fall back to LAN IP
    final lanIp = await getLanIp();
    if (lanIp != null) {
      print('Using LAN IP: $lanIp');
      return lanIp;
    }

    // Last resort - localhost won't work for mobile but at least won't crash
    print('Warning: No network IP found, using localhost');
    return 'localhost';
  }

  /// Get LAN IP address (for when Tailscale isn't available)
  /// 
  /// Returns the first private network IP address found (192.168.x.x, 10.x.x.x, 172.x.x.x)
  Future<String?> getLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        // Skip loopback interfaces
        if (interface.name == 'lo' || interface.name == 'lo0') continue;
        // Skip Tailscale interfaces (already handled by getTailscaleIp)
        if (interface.name.startsWith('utun')) continue;

        for (final addr in interface.addresses) {
          final ip = addr.address;
          // Skip loopback addresses
          if (ip.startsWith('127.')) continue;
          // Prefer private network addresses
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              _isPrivate172(ip)) {
            return ip;
          }
        }
      }
    } catch (e) {
      print('Error getting LAN IP: $e');
    }
    return null;
  }

  /// Check if IP is in the 172.16.0.0 - 172.31.255.255 private range
  bool _isPrivate172(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final secondOctet = int.tryParse(parts[1]);
    if (secondOctet == null) return false;
    return secondOctet >= 16 && secondOctet <= 31;
  }

  /// Get the Tailscale IP address by checking network interfaces
  Future<String?> getTailscaleIp() async {
    try {
      // Use ifconfig to get network interfaces (no sudo required)
      final result = await Process.run('ifconfig', []);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final ip = _extractTailscaleIp(output);

        if (ip != null) {
          return ip;
        }
      }
    } catch (e) {
      // Silently fail - Tailscale is optional
    }

    return null;
  }

  /// Extract Tailscale IP from ifconfig output
  String? _extractTailscaleIp(String ifconfigOutput) {
    final lines = ifconfigOutput.split('\n');
    bool inTailscaleInterface = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Tailscale typically uses utun interfaces on macOS
      if (line.startsWith('utun') && line.contains(':')) {
        inTailscaleInterface = true;
      } else if (line.startsWith(RegExp(r'[a-z]')) && !line.startsWith('\t') && !line.startsWith(' ')) {
        // New interface started, reset flag
        inTailscaleInterface = false;
      }

      // Look for inet line with 100.x.x.x (Tailscale CGNAT range)
      if (inTailscaleInterface && line.trim().startsWith('inet ')) {
        final parts = line.trim().split(' ');
        if (parts.length >= 2) {
          final ip = parts[1];
          // Tailscale uses 100.64.0.0/10 CGNAT range
          if (ip.startsWith('100.')) {
            return ip;
          }
        }
      }
    }

    return null;
  }

  /// Check if Tailscale is installed
  Future<bool> isTailscaleInstalled() async {
    final path = await _findTailscalePath();
    return path != null;
  }

  /// Check if Tailscale is running
  Future<bool> isTailscaleRunning() async {
    final ip = await getTailscaleIp();
    return ip != null;
  }

  /// Find the Tailscale binary path
  Future<String?> _findTailscalePath() async {
    // Common Tailscale installation paths
    final possiblePaths = [
      '/opt/homebrew/bin/tailscale',
      '/usr/local/bin/tailscale',
      '/usr/bin/tailscale',
      'C:\\Program Files\\Tailscale\\tailscale.exe', // Windows
    ];

    // Check each path
    for (final path in possiblePaths) {
      if (await File(path).exists()) {
        return path;
      }
    }

    // Try using 'which' on Unix-like systems
    if (!Platform.isWindows) {
      try {
        final result = await Process.run('which', ['tailscale']);
        if (result.exitCode == 0) {
          final path = result.stdout.toString().trim();
          if (path.isNotEmpty) {
            return path;
          }
        }
      } catch (e) {
        // Ignore and continue
      }
    }

    // Try using 'where' on Windows
    if (Platform.isWindows) {
      try {
        final result = await Process.run('where', ['tailscale']);
        if (result.exitCode == 0) {
          final path = result.stdout.toString().trim();
          if (path.isNotEmpty) {
            return path.split('\n').first.trim();
          }
        }
      } catch (e) {
        // Ignore and continue
      }
    }

    return null;
  }

  /// Get Tailscale status as a map (for API endpoint)
  Future<Map<String, dynamic>> getStatus() async {
    final isInstalled = await isTailscaleInstalled();
    final isRunning = await isTailscaleRunning();
    final ip = await getTailscaleIp();

    return {
      'isInstalled': isInstalled,
      'isRunning': isRunning,
      'ip': ip,
    };
  }
}
