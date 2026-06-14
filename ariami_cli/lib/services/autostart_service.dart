import 'dart:io';

import 'package:path/path.dart' as path;

import 'cli_state_service.dart';

/// Service for managing whether the Ariami CLI server starts automatically when
/// the machine boots.
///
/// Uses the standard, no-root mechanism on each platform:
///   - Linux:   an `@reboot` crontab entry (works headless without an active
///              login session; standard on Raspberry Pi OS)
///   - macOS:   a LaunchAgent plist in ~/Library/LaunchAgents with RunAtLoad
///   - Windows: an HKCU ...\CurrentVersion\Run registry value
class AutostartService {
  static final AutostartService _instance = AutostartService._internal();
  factory AutostartService() => _instance;
  AutostartService._internal();

  /// Marker used to identify our entries in shared stores (crontab/registry).
  static const String _marker = 'ariami-cli-autostart';

  /// macOS LaunchAgent label / plist filename.
  static const String _launchAgentLabel = 'com.ariami.cli';

  /// Whether the current platform is supported.
  bool get isSupported =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  /// Build the command (executable + args) that should run at boot.
  /// Mirrors DaemonService's detection of compiled vs `dart run` execution.
  (String, List<String>) _bootCommand() {
    final script = Platform.script;
    final executable = Platform.resolvedExecutable;

    if (script.path.endsWith('.dart')) {
      return (executable, ['run', script.toFilePath(), 'start']);
    }
    return (executable, ['start']);
  }

  /// Enable starting the server at boot. Returns true on success.
  Future<bool> enable() async {
    try {
      if (Platform.isLinux) return await _enableLinux();
      if (Platform.isMacOS) return await _enableMacOS();
      if (Platform.isWindows) return await _enableWindows();
    } catch (e) {
      stderr.writeln('Failed to enable start-at-boot: $e');
    }
    return false;
  }

  /// Disable starting the server at boot. Returns true on success.
  Future<bool> disable() async {
    try {
      if (Platform.isLinux) return await _disableLinux();
      if (Platform.isMacOS) return await _disableMacOS();
      if (Platform.isWindows) return await _disableWindows();
    } catch (e) {
      stderr.writeln('Failed to disable start-at-boot: $e');
    }
    return false;
  }

  /// Whether start-at-boot is currently configured.
  Future<bool> isEnabled() async {
    try {
      if (Platform.isLinux) return await _isEnabledLinux();
      if (Platform.isMacOS) return _isEnabledMacOS();
      if (Platform.isWindows) return await _isEnabledWindows();
    } catch (_) {
      // Ignore - treat as not enabled.
    }
    return false;
  }

  // ==========================================================================
  // Linux (crontab @reboot)
  // ==========================================================================

  String _shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  String _linuxCronLine() {
    final (executable, args) = _bootCommand();
    final logPath = path.join(CliStateService.getConfigDir(), 'autostart.log');
    final command = [executable, ...args].map(_shellQuote).join(' ');
    return '@reboot $command >> ${_shellQuote(logPath)} 2>&1 # $_marker';
  }

  Future<String> _readCrontab() async {
    final result = await Process.run('crontab', ['-l']);
    // Exit code 1 with "no crontab" message is normal when empty.
    if (result.exitCode != 0) return '';
    return result.stdout.toString();
  }

  Future<void> _writeCrontab(String content) async {
    final process = await Process.start('crontab', ['-']);
    process.stdin.write(content);
    await process.stdin.close();
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('crontab write failed (exit $exitCode)');
    }
  }

  List<String> _crontabLinesWithoutMarker(String crontab) {
    return crontab
        .split('\n')
        .where((line) => !line.contains(_marker))
        .toList();
  }

  Future<bool> _enableLinux() async {
    final existing = await _readCrontab();
    final lines = _crontabLinesWithoutMarker(existing)
      ..removeWhere((line) => line.trim().isEmpty);
    lines.add(_linuxCronLine());
    await _writeCrontab('${lines.join('\n')}\n');
    return true;
  }

  Future<bool> _disableLinux() async {
    final existing = await _readCrontab();
    if (!existing.contains(_marker)) return true;
    final lines = _crontabLinesWithoutMarker(existing)
      ..removeWhere((line) => line.trim().isEmpty);
    await _writeCrontab(lines.isEmpty ? '' : '${lines.join('\n')}\n');
    return true;
  }

  Future<bool> _isEnabledLinux() async {
    final existing = await _readCrontab();
    return existing.contains(_marker);
  }

  // ==========================================================================
  // macOS (LaunchAgent)
  // ==========================================================================

  String _launchAgentPath() {
    final home = Platform.environment['HOME'] ?? '';
    return path.join(home, 'Library', 'LaunchAgents', '$_launchAgentLabel.plist');
  }

  String _launchAgentPlist() {
    final (executable, args) = _bootCommand();
    final logPath = path.join(CliStateService.getConfigDir(), 'autostart.log');
    final programArgs = [executable, ...args]
        .map((a) => '    <string>${_xmlEscape(a)}</string>')
        .join('\n');
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_launchAgentLabel</string>
  <key>ProgramArguments</key>
  <array>
$programArgs
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_xmlEscape(logPath)}</string>
  <key>StandardErrorPath</key>
  <string>${_xmlEscape(logPath)}</string>
</dict>
</plist>
''';
  }

  String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  Future<bool> _enableMacOS() async {
    final plistPath = _launchAgentPath();
    final file = File(plistPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(_launchAgentPlist());
    // Reload so it is registered for the current session too.
    await Process.run('launchctl', ['unload', plistPath]);
    await Process.run('launchctl', ['load', '-w', plistPath]);
    return true;
  }

  Future<bool> _disableMacOS() async {
    final plistPath = _launchAgentPath();
    final file = File(plistPath);
    if (await file.exists()) {
      await Process.run('launchctl', ['unload', '-w', plistPath]);
      await file.delete();
    }
    return true;
  }

  bool _isEnabledMacOS() {
    return File(_launchAgentPath()).existsSync();
  }

  // ==========================================================================
  // Windows (HKCU Run registry key)
  // ==========================================================================

  static const String _windowsRunKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _windowsValueName = 'AriamiCLI';

  String _windowsCommand() {
    final (executable, args) = _bootCommand();
    final quoted = [executable, ...args].map((a) => '"$a"').join(' ');
    return quoted;
  }

  Future<bool> _enableWindows() async {
    final result = await Process.run('reg', [
      'add',
      _windowsRunKey,
      '/v',
      _windowsValueName,
      '/t',
      'REG_SZ',
      '/d',
      _windowsCommand(),
      '/f',
    ]);
    return result.exitCode == 0;
  }

  Future<bool> _disableWindows() async {
    final result = await Process.run('reg', [
      'delete',
      _windowsRunKey,
      '/v',
      _windowsValueName,
      '/f',
    ]);
    // Exit code 1 when the value does not exist is acceptable.
    return result.exitCode == 0 ||
        result.stderr.toString().contains('unable to find');
  }

  Future<bool> _isEnabledWindows() async {
    final result = await Process.run('reg', [
      'query',
      _windowsRunKey,
      '/v',
      _windowsValueName,
    ]);
    return result.exitCode == 0;
  }
}
