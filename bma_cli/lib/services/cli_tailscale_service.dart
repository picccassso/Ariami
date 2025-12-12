import 'dart:io';

/// Service for managing Tailscale detection and IP address resolution on CLI (cross-platform)
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
        if (_isTailscaleInterface(interface.name)) continue;

        for (final addr in interface.addresses) {
          final ip = addr.address;
          // Skip loopback addresses
          if (ip.startsWith('127.')) continue;
          // Skip Tailscale CGNAT addresses
          if (_isTailscaleCgnatIp(ip)) continue;
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

  /// Check if interface name is a Tailscale interface (cross-platform)
  bool _isTailscaleInterface(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith('utun') || // macOS
        lower.startsWith('tailscale') || // Linux (tailscale0)
        lower.startsWith('ts') || // Linux (ts0)
        lower.contains('tailscale'); // Windows
  }

  /// Get the Tailscale IP address using cross-platform detection
  ///
  /// Primary method: `tailscale ip -4` CLI command
  /// Fallback: NetworkInterface scanning for CGNAT range (100.64.0.0/10)
  Future<String?> getTailscaleIp() async {
    // Method 1: Try the Tailscale CLI (most reliable, works on all platforms)
    final cliIp = await _getTailscaleIpViaCli();
    if (cliIp != null) {
      return cliIp;
    }

    // Method 2: Fall back to network interface scanning
    return await _getTailscaleIpViaNetworkInterface();
  }

  /// Get Tailscale IP using the `tailscale ip -4` command
  /// Works on macOS, Linux, and Windows
  Future<String?> _getTailscaleIpViaCli() async {
    try {
      final executable = Platform.isWindows ? 'tailscale.exe' : 'tailscale';
      final result = await Process.run(executable, ['ip', '-4']);

      if (result.exitCode == 0) {
        final ip = result.stdout.toString().trim();
        if (ip.isNotEmpty && _isTailscaleCgnatIp(ip)) {
          return ip;
        }
      }
    } catch (e) {
      // CLI not available, fall back to network interface method
    }
    return null;
  }

  /// Get Tailscale IP by scanning network interfaces for CGNAT range
  /// Platform-agnostic: doesn't rely on interface names
  Future<String?> _getTailscaleIpViaNetworkInterface() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (_isTailscaleCgnatIp(ip)) {
            return ip;
          }
        }
      }
    } catch (e) {
      // Silently fail - Tailscale is optional
    }
    return null;
  }

  /// Check if IP is in Tailscale's CGNAT range (100.64.0.0/10)
  /// Range: 100.64.0.0 - 100.127.255.255
  bool _isTailscaleCgnatIp(String ip) {
    if (!ip.startsWith('100.')) return false;

    final parts = ip.split('.');
    if (parts.length != 4) return false;

    final secondOctet = int.tryParse(parts[1]);
    if (secondOctet == null) return false;

    // CGNAT range: 100.64.0.0/10 means second octet is 64-127
    return secondOctet >= 64 && secondOctet <= 127;
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

  /// Find the Tailscale binary path (cross-platform)
  Future<String?> _findTailscalePath() async {
    // Common Tailscale installation paths
    final possiblePaths = [
      '/opt/homebrew/bin/tailscale', // macOS Homebrew ARM
      '/usr/local/bin/tailscale', // macOS Homebrew Intel
      '/usr/bin/tailscale', // Linux
      '/usr/sbin/tailscale', // Linux (some distros)
      r'C:\Program Files\Tailscale\tailscale.exe', // Windows
      r'C:\Program Files (x86)\Tailscale\tailscale.exe', // Windows 32-bit
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
