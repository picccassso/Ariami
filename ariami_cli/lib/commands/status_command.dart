import 'dart:io';

import '../services/server_status_service.dart';
import '../services/cli_guidance.dart';

/// Command to check the Ariami CLI server status.
class StatusCommand {
  final ServerStatusService _statusService = ServerStatusService();

  /// Execute the status command.
  Future<void> execute() async {
    try {
      final snapshot = await _statusService.collectSnapshot();
      for (final line in ServerStatusService.formatStatus(snapshot)) {
        stdout.writeln(line);
      }
      stdout.writeln('Next:      ${CliGuidance.nextStep(
        isRunning: snapshot.isRunning,
        setupComplete: snapshot.setupComplete,
        hasOwnerAccount: snapshot.hasOwnerAccount == true,
      )}');
    } catch (_) {
      stdout.writeln('Ariami CLI ${ServerStatusService.cliVersion}');
      stdout.writeln('Server:    status unavailable');
    }
  }
}
