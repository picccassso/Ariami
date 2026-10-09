import 'dart:io';

enum TailscaleStatus {
  connected,
  notDetected,
  installedNotConnected,
  checking,
}

class MobileTailscaleService {
  Future<TailscaleStatus> checkTailscaleStatus() async {
    try {
      final isVpnConnected = await _checkVpnConnection();

      if (isVpnConnected) {
        // If VPN is connected, assume it's Tailscale
        return TailscaleStatus.connected;
      }

      final isTailscaleInstalled = await _isTailscaleInstalled();

      if (isTailscaleInstalled) {
        return TailscaleStatus.installedNotConnected;
      }

      return TailscaleStatus.notDetected;
    } catch (e) {
      return TailscaleStatus.notDetected;
    }
  }

  Future<bool> _checkVpnConnection() async {
    try {
      if (Platform.isAndroid) {
        return await _checkAndroidVpn();
      } else if (Platform.isIOS) {
        return await _checkIOSVpn();
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkAndroidVpn() async {
    try {
      final interfaces = await NetworkInterface.list();

      // Look for tun0 interface (typical VPN interface)
      for (var interface in interfaces) {
        if (interface.name.toLowerCase().contains('tun') ||
            interface.name.toLowerCase().contains('tailscale')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkIOSVpn() async {
    try {
      final interfaces = await NetworkInterface.list();

      for (var interface in interfaces) {
        if (interface.name.toLowerCase().contains('utun')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _isTailscaleInstalled() async {
    try {
      if (Platform.isAndroid) {
        return await _isAndroidAppInstalled();
      } else if (Platform.isIOS) {
        return await _isIOSAppInstalled();
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _isAndroidAppInstalled() async {
    // Note: This would require a platform channel to properly check
    // For now, we'll rely on VPN connection check
    return false;
  }

  Future<bool> _isIOSAppInstalled() async {
    // Note: This would require a platform channel to properly check
    // For now, we'll rely on VPN connection check
    return false;
  }

  String getInstallUrl() {
    if (Platform.isAndroid) {
      return 'https://play.google.com/store/apps/details?id=com.tailscale.ipn';
    } else if (Platform.isIOS) {
      return 'https://apps.apple.com/us/app/tailscale/id1470499037';
    }
    return '';
  }

  List<String> getSetupInstructions() {
    if (Platform.isAndroid) {
      return [
        'Install Tailscale from Google Play',
        'Grant VPN permissions to Tailscale',
        'Sign in to your Tailscale account',
        'Ensure VPN is connected',
      ];
    } else if (Platform.isIOS) {
      return [
        'Install Tailscale from the App Store',
        'Enable VPN in Settings > Tailscale',
        'Sign in to your Tailscale account',
        'Ensure VPN is active',
      ];
    }
    return [];
  }
}
