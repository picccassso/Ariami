import 'dart:io';

import '../services/autostart_service.dart';

/// Command to manage whether the Ariami server starts automatically on boot.
///
/// This is the way existing installs (set up before the boot prompt existed)
/// can enable start-on-boot without re-running setup.
class AutostartCommand {
  final AutostartService _autostartService = AutostartService();

  /// Execute the autostart command. [action] is one of:
  /// `enable`, `disable`, `status` (defaults to `status`).
  Future<void> execute({String action = 'status'}) async {
    if (!_autostartService.isSupported) {
      print('Start-on-boot is not supported on this platform.');
      return;
    }

    switch (action) {
      case 'enable':
      case 'on':
        final ok = await _autostartService.enable();
        if (ok) {
          print('✓ Ariami will now start automatically on boot.');
        } else {
          print('ERROR: Could not enable start-on-boot.');
          exit(1);
        }
        break;
      case 'disable':
      case 'off':
        final ok = await _autostartService.disable();
        if (ok) {
          print('✓ Ariami will no longer start automatically on boot.');
        } else {
          print('ERROR: Could not disable start-on-boot.');
          exit(1);
        }
        break;
      case 'status':
        final enabled = await _autostartService.isEnabled();
        print('Start on boot: ${enabled ? "Enabled" : "Disabled"}');
        break;
      default:
        print('Error: unknown autostart action "$action".');
        print('');
        print('Usage: ariami_cli autostart [enable|disable|status]');
        exit(1);
    }
  }
}
