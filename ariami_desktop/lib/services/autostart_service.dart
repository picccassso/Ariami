import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

/// Service for managing whether Ariami Desktop launches automatically when the
/// user logs in / the machine boots.
///
/// Backed by the `launch_at_startup` package, which uses the native mechanism on
/// each platform:
///   - macOS:   SMAppService (Login Items, macOS 13+)
///   - Windows: HKCU \Software\Microsoft\Windows\CurrentVersion\Run registry key
///   - Linux:   a `~/.config/autostart/<app>.desktop` entry
class AutostartService {
  static final AutostartService _instance = AutostartService._internal();
  factory AutostartService() => _instance;
  AutostartService._internal();

  bool _isConfigured = false;

  /// Whether the current platform supports launch-at-startup.
  bool get isSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Configure the underlying launcher with this app's identity. Idempotent.
  void _ensureConfigured() {
    if (_isConfigured || !isSupported) return;

    launchAtStartup.setup(
      appName: 'Ariami Desktop',
      appPath: Platform.resolvedExecutable,
      packageName: 'com.example.ariamiDesktop',
    );
    _isConfigured = true;
  }

  /// Whether the app is currently registered to launch at startup.
  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    _ensureConfigured();
    try {
      return await launchAtStartup.isEnabled();
    } catch (e) {
      print('[Autostart] Failed to read launch-at-startup state: $e');
      return false;
    }
  }

  /// Enable or disable launching the app at startup.
  /// Returns the resulting enabled state.
  Future<bool> setEnabled(bool enabled) async {
    if (!isSupported) return false;
    _ensureConfigured();
    try {
      if (enabled) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      return await launchAtStartup.isEnabled();
    } catch (e) {
      print('[Autostart] Failed to ${enabled ? 'enable' : 'disable'} '
          'launch-at-startup: $e');
      rethrow;
    }
  }
}
