import 'dart:io';
import 'dart:convert';
import 'cli_state_service.dart';

/// Service for managing the daemon process (background server)
class DaemonService {
  // Singleton pattern
  static final DaemonService _instance = DaemonService._internal();
  factory DaemonService() => _instance;
  DaemonService._internal();

  final CliStateService _stateService = CliStateService();

  /// Check if the server is running
  Future<bool> isRunning() async {
    await _stateService.ensureConfigDir();
    final pidFile = File(CliStateService.getPidFilePath());

    if (!await pidFile.exists()) {
      return false;
    }

    try {
      final pidString = await pidFile.readAsString();
      final pid = int.tryParse(pidString.trim());

      if (pid == null) {
        return false;
      }

      // Check if process with this PID exists
      return _isProcessRunning(pid);
    } catch (e) {
      return false;
    }
  }

  /// Check if a process with the given PID is running
  bool _isProcessRunning(int pid) {
    try {
      // Send signal 0 to check if process exists (doesn't actually kill it)
      // This works on Unix-like systems (macOS, Linux)
      if (Platform.isLinux || Platform.isMacOS) {
        final result = Process.runSync('kill', ['-0', pid.toString()]);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        // On Windows, use tasklist to check if process exists
        final result = Process.runSync('tasklist', ['/FI', 'PID eq $pid', '/NH']);
        return result.stdout.toString().contains(pid.toString());
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get the current server PID
  Future<int?> getServerPid() async {
    await _stateService.ensureConfigDir();
    final pidFile = File(CliStateService.getPidFilePath());

    if (!await pidFile.exists()) {
      return null;
    }

    try {
      final pidString = await pidFile.readAsString();
      return int.tryParse(pidString.trim());
    } catch (e) {
      return null;
    }
  }

  /// Save the server PID
  Future<void> saveServerPid(int pid) async {
    await _stateService.ensureConfigDir();
    final pidFile = File(CliStateService.getPidFilePath());
    await pidFile.writeAsString(pid.toString());
  }

  /// Remove the PID file
  Future<void> removePidFile() async {
    final pidFile = File(CliStateService.getPidFilePath());
    if (await pidFile.exists()) {
      await pidFile.delete();
    }
  }

  /// Save server state (port, Tailscale IP, etc.)
  Future<void> saveServerState(Map<String, dynamic> state) async {
    await _stateService.ensureConfigDir();
    final stateFile = File(CliStateService.getServerStateFilePath());
    await stateFile.writeAsString(jsonEncode(state));
  }

  /// Get server state
  Future<Map<String, dynamic>?> getServerState() async {
    final stateFile = File(CliStateService.getServerStateFilePath());

    if (!await stateFile.exists()) {
      return null;
    }

    try {
      final content = await stateFile.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Stop the server gracefully
  Future<bool> stopServer() async {
    final pid = await getServerPid();

    if (pid == null) {
      return false;
    }

    try {
      if (Platform.isLinux || Platform.isMacOS) {
        // Send SIGTERM for graceful shutdown
        Process.runSync('kill', ['-TERM', pid.toString()]);
      } else if (Platform.isWindows) {
        // On Windows, use taskkill
        Process.runSync('taskkill', ['/PID', pid.toString(), '/F']);
      }

      // Wait a bit for process to stop
      await Future.delayed(const Duration(milliseconds: 500));

      // Clean up PID file
      await removePidFile();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Detect if running as compiled executable or via dart run
  /// Returns (executable, args) tuple for spawning background process
  (String, List<String>) _buildBackgroundCommand(List<String> flags) {
    final script = Platform.script;
    final executable = Platform.resolvedExecutable;

    // If script ends with .dart, we're running via dart run
    if (script.path.endsWith('.dart')) {
      // Running via dart run
      return (executable, ['run', script.toFilePath(), ...flags]);
    } else {
      // Running as compiled executable
      return (executable, flags);
    }
  }

  /// Start the server in the background
  /// Returns the process PID
  Future<int?> startServerInBackground(List<String> flags) async {
    try {
      // Build correct command based on execution mode
      final (executable, args) = _buildBackgroundCommand(flags);

      // On Linux, use nohup + setsid for proper daemonization
      // ProcessStartMode.detached doesn't fully detach on Linux
      if (Platform.isLinux) {
        return await _startServerOnLinux(executable, args);
      }

      // On macOS/Windows, ProcessStartMode.detached works correctly
      final process = await Process.start(
        executable,
        args,
        mode: ProcessStartMode.detached,
      );

      // Save the PID
      await saveServerPid(process.pid);

      return process.pid;
    } catch (e) {
      print('Error starting server in background: $e');
      return null;
    }
  }

  /// Linux-specific daemon spawning using nohup + setsid
  /// This properly detaches the process from the terminal session
  Future<int?> _startServerOnLinux(String executable, List<String> args) async {
    try {
      // Get the working directory (where the executable is located)
      final executableFile = File(executable);
      final workingDir = executableFile.parent.path;

      // Build the command string
      final argsString = args.map((a) => '"$a"').join(' ');

      // Use setsid to create new session, nohup to ignore SIGHUP
      // Redirect output to /dev/null, run in background, echo PID
      final shellCommand = 'cd "$workingDir" && nohup setsid "$executable" $argsString > /dev/null 2>&1 & echo \$!';

      // Run through bash to get proper shell features
      final result = await Process.run(
        '/bin/bash',
        ['-c', shellCommand],
      );

      if (result.exitCode != 0) {
        print('Failed to start background process: ${result.stderr}');
        return null;
      }

      // Parse the PID from stdout
      final pidString = result.stdout.toString().trim();
      final pid = int.tryParse(pidString);

      if (pid == null) {
        print('Failed to parse PID from output: $pidString');
        return null;
      }

      // Save the PID
      await saveServerPid(pid);

      return pid;
    } catch (e) {
      print('Error starting server on Linux: $e');
      return null;
    }
  }
}
