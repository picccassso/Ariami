import '../services/daemon_service.dart';

/// Command to stop the Ariami CLI server
class StopCommand {
  final DaemonService _daemonService = DaemonService();

  /// Execute the stop command
  Future<void> execute() async {
    // Check if running
    if (!await _daemonService.isRunning()) {
      print('Ariami CLI server is not running.');
      return;
    }

    print('Stopping Ariami CLI server...');

    final success = await _daemonService.stopServer();

    if (success) {
      print('Ariami CLI server stopped successfully.');
    } else {
      print('Failed to stop Ariami CLI server.');
      print('The server may have already stopped or requires manual intervention.');
    }
  }
}
