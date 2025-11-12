import 'dart:io';
import 'package:flutter/services.dart';

enum TailscaleStatus {
  connected,
  notDetected,
  installedNotConnected,
  checking,
}

class MobileTailscaleService {
  /// Check if Tailscale is installed and connected
  Future<TailscaleStatus> checkTailscaleStatus() async {
    try {
      // Check VPN connection status
      final isVpnConnected = await _checkVpnConnection();

      if (isVpnConnected) {
        // If VPN is connected, assume it's Tailscale
        return TailscaleStatus.connected;
      }

      // Check if Tailscale app is installed
      final isTailscaleInstalled = await _isTailscaleInstalled();

      if (isTailscaleInstalled) {
        return TailscaleStatus.installedNotConnected;
      }

      return TailscaleStatus.notDetected;
    } catch (e) {
      return TailscaleStatus.notDetected;
    }
  }

  /// Check if VPN is connected (platform-specific)
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

  /// Check VPN connection on Android
  Future<bool> _checkAndroidVpn() async {
    try {
      // Check for active network interfaces
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

  /// Check VPN connection on iOS
  Future<bool> _checkIOSVpn() async {
    try {
      // Check for utun interfaces (iOS VPN)
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

  /// Check if Tailscale app is installed
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

  /// Check if Tailscale is installed on Android
  Future<bool> _isAndroidAppInstalled() async {
    // Note: This would require a platform channel to properly check
    // For now, we'll rely on VPN connection check
    return false;
  }

  /// Check if Tailscale is installed on iOS
  Future<bool> _isIOSAppInstalled() async {
    // Note: This would require a platform channel to properly check
    // For now, we'll rely on VPN connection check
    return false;
  }

  /// Get platform-specific installation URL
  String getInstallUrl() {
    if (Platform.isAndroid) {
      return 'https://play.google.com/store/apps/details?id=com.tailscale.ipn';
    } else if (Platform.isIOS) {
      return 'https://apps.apple.com/us/app/tailscale/id1470499037';
    }
    return '';
  }

  /// Get platform-specific instructions
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
