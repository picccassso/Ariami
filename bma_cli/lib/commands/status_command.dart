import '../services/daemon_service.dart';
import '../services/cli_state_service.dart';

/// Command to check the BMA CLI server status
class StatusCommand {
  final DaemonService _daemonService = DaemonService();
  final CliStateService _stateService = CliStateService();

  /// Execute the status command
  Future<void> execute() async {
    print('BMA CLI Server Status');
    print('====================');
    print('');

    // Check if running
    final isRunning = await _daemonService.isRunning();
    print('Status: ${isRunning ? "Running" : "Stopped"}');

    if (isRunning) {
      // Show PID
      final pid = await _daemonService.getServerPid();
      if (pid != null) {
        print('PID: $pid');
      }

      // Show server state
      final state = await _daemonService.getServerState();
      if (state != null) {
        if (state['port'] != null) {
          print('Port: ${state['port']}');
        }
        if (state['tailscale_ip'] != null) {
          print('Tailscale IP: ${state['tailscale_ip']}');
        }
        if (state['music_folder_path'] != null) {
          print('Music Folder: ${state['music_folder_path']}');
        }
      }
    }

    // Check setup status
    final isSetupComplete = await _stateService.isSetupComplete();
    print('Setup Complete: ${isSetupComplete ? "Yes" : "No"}');

    // Show music folder path
    final musicFolderPath = await _stateService.getMusicFolderPath();
    if (musicFolderPath != null) {
      print('Music Library: $musicFolderPath');
    }

    print('');
    print('Configuration Directory: ${CliStateService.getConfigDir()}');
  }
}
