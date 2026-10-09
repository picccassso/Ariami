import 'dart:io';

/// Tailscale / LAN address discovery shared by the CLI and desktop hosts.
class TailscaleLocator {
  const TailscaleLocator._();

  /// Install locations probed (in order) before falling back to `which`/`where`.
  static const defaultBinaryCandidates = <String>[
    '/opt/homebrew/bin/tailscale', // macOS Homebrew ARM
    '/usr/local/bin/tailscale', // macOS Homebrew Intel
    '/usr/bin/tailscale', // Linux
    '/usr/sbin/tailscale', // Linux (some distros)
    r'C:\Program Files\Tailscale\tailscale.exe', // Windows
    r'C:\Program Files (x86)\Tailscale\tailscale.exe', // Windows 32-bit
  ];

  /// Get the Tailscale IP via `tailscale ip -4`, falling back to scanning
  /// network interfaces for the CGNAT range. [log] receives detection notes.
  static Future<String?> getTailscaleIp({void Function(String)? log}) async {
    final cliIp = await _viaCli();
    if (cliIp != null) {
      log?.call('Tailscale IP (via CLI): $cliIp');
      return cliIp;
    }

    final interfaceIp = await _viaNetworkInterface();
    if (interfaceIp != null) {
      log?.call('Tailscale IP (via interface): $interfaceIp');
      return interfaceIp;
    }

    log?.call('Tailscale IP not found');
    return null;
  }

  /// First private-range IPv4 address. With [skipTailscaleInterfaces], loopback
  /// and Tailscale-named interfaces are skipped; [onError] receives failures.
  static Future<String?> getLanIp({
    bool skipTailscaleInterfaces = false,
    void Function(Object error)? onError,
  }) async {
    try {
      for (final interface in await _listInterfaces()) {
        if (skipTailscaleInterfaces &&
            (interface.name == 'lo' ||
                interface.name == 'lo0' ||
                _isTailscaleInterface(interface.name))) {
          continue;
        }
        for (final addr in interface.addresses) {
          if (_isLanIp(addr.address)) return addr.address;
        }
      }
    } catch (e) {
      onError?.call(e);
    }
    return null;
  }

  /// Path of the tailscale binary, or null when it cannot be found.
  static Future<String?> findBinary({
    List<String> candidates = defaultBinaryCandidates,
  }) async {
    for (final path in candidates) {
      if (await File(path).exists()) {
        return path;
      }
    }

    final lookup = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(lookup, ['tailscale']);
      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty) {
          return Platform.isWindows ? path.split('\n').first.trim() : path;
        }
      }
    } catch (e) {
      // Ignore and continue
    }

    return null;
  }

  static Future<String?> _viaCli() async {
    try {
      final executable = Platform.isWindows ? 'tailscale.exe' : 'tailscale';
      final result = await Process.run(executable, ['ip', '-4']);

      if (result.exitCode == 0) {
        final ip = result.stdout.toString().trim();
        if (ip.isNotEmpty && isTailscaleCgnatIp(ip)) {
          return ip;
        }
      }
    } catch (e) {
      // CLI not available, fall back to network interface method
    }
    return null;
  }

  static Future<String?> _viaNetworkInterface() async {
    try {
      for (final interface in await _listInterfaces()) {
        for (final addr in interface.addresses) {
          if (isTailscaleCgnatIp(addr.address)) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      // Network interface listing failed
    }
    return null;
  }

  static Future<List<NetworkInterface>> _listInterfaces() =>
      NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

  /// True for Tailscale's CGNAT range (100.64.0.0/10).
  static bool isTailscaleCgnatIp(String ip) {
    final second = _secondOctet(ip, '100.');
    return second != null && second >= 64 && second <= 127;
  }

  static bool _isLanIp(String ip) {
    if (ip.startsWith('127.') || isTailscaleCgnatIp(ip)) return false;
    return ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        _isPrivate172(ip);
  }

  static bool _isPrivate172(String ip) {
    final second = _secondOctet(ip, '172.');
    return second != null && second >= 16 && second <= 31;
  }

  static int? _secondOctet(String ip, String prefix) {
    if (!ip.startsWith(prefix)) return null;
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return int.tryParse(parts[1]);
  }

  static bool _isTailscaleInterface(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith('utun') || // macOS
        lower.startsWith('tailscale') || // Linux (tailscale0)
        lower.startsWith('ts') || // Linux (ts0)
        lower.contains('tailscale'); // Windows
  }
}
