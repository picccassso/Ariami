import 'dart:io';

/// Simple service to check Tailscale connectivity on desktop
class TailscaleService {
  /// Check if Tailscale is connected by looking for Tailscale IP
  Future<bool> isConnected() async {
    try {
      final interfaces = await NetworkInterface.list();

      for (var interface in interfaces) {
        // Tailscale interface is typically named "utun" on macOS or "tailscale0" on Linux
        if (interface.name.contains('utun') ||
            interface.name.contains('tailscale')) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4) {
              // Tailscale IPs are in the 100.x.x.x range
              if (addr.address.startsWith('100.')) {
                return true;
              }
            }
          }
        }
      }

      // Fallback: try to find any IP in the Tailscale range
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              addr.address.startsWith('100.')) {
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}
