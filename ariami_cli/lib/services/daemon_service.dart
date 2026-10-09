import 'dart:io';
import 'dart:convert';
import 'cli_state_service.dart';

class DaemonService {
  static final DaemonService _instance = DaemonService._internal();
  factory DaemonService() => _instance;
  DaemonService._internal();

  final CliStateService _stateService = CliStateService();

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

      return _isProcessRunning(pid);
    } catch (e) {
      return false;
    }
  }

  bool _isProcessRunning(int pid) {
    try {
      // Send signal 0 to check if process exists (doesn't actually kill it)
      // This works on Unix-like systems (macOS, Linux)
      if (Platform.isLinux || Platform.isMacOS) {
        final result = Process.runSync('kill', ['-0', pid.toString()]);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final result = Process.runSync('tasklist', ['/FI', 'PID eq $pid', '/NH']);
        return result.stdout.toString().contains(pid.toString());
      }
      return false;
    } catch (e) {
      return false;
    }
  }

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

  Future<void> saveServerPid(int pid) async {
    await _stateService.ensureConfigDir();
    final pidFile = File(CliStateService.getPidFilePath());
    await pidFile.writeAsString(pid.toString());
  }

  Future<void> removePidFile() async {
    final pidFile = File(CliStateService.getPidFilePath());
    if (await pidFile.exists()) {
      await pidFile.delete();
    }
  }

  Future<void> saveServerState(Map<String, dynamic> state) async {
    await _stateService.ensureConfigDir();
    final stateFile = File(CliStateService.getServerStateFilePath());
    await stateFile.writeAsString(jsonEncode(state));
  }

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

  Future<bool> stopServer() async {
    final pid = await getServerPid();

    if (pid == null) {
      return false;
    }

    try {
      if (Platform.isLinux || Platform.isMacOS) {
        Process.runSync('kill', ['-TERM', pid.toString()]);
      } else if (Platform.isWindows) {
        Process.runSync('taskkill', ['/PID', pid.toString(), '/F']);
      }

      await Future.delayed(const Duration(milliseconds: 500));

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

    if (script.path.endsWith('.dart')) {
      return (executable, ['run', script.toFilePath(), ...flags]);
    } else {
      return (executable, flags);
    }
  }

  Future<int?> startServerInBackground(List<String> flags) async {
    try {
      final (executable, args) = _buildBackgroundCommand(flags);

      // On Linux, use setsid for proper daemonization
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

      await saveServerPid(process.pid);

      return process.pid;
    } catch (e) {
      print('Error starting server in background: $e');
      return null;
    }
  }

  /// Linux-specific daemon spawning using setsid
  /// This properly detaches the process from the terminal session
  Future<int?> _startServerOnLinux(String executable, List<String> args) async {
    try {
      final executableFile = File(executable);
      final workingDir = executableFile.parent.path;

      // Use setsid directly (no shell). This creates a new session and
      // fully detaches from the controlling terminal, then execs the server.
      final process = await Process.start(
        'setsid',
        [executable, ...args],
        mode: ProcessStartMode.detached,
        workingDirectory: workingDir,
      );

      // Save the PID (setsid execs the server, so PID remains correct)
      await saveServerPid(process.pid);

      return process.pid;
    } catch (e) {
      print('Error starting server on Linux: $e');
      return null;
    }
  }
}
