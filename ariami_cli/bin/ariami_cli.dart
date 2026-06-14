import 'dart:io';
import 'package:args/args.dart';
import 'package:ariami_cli/commands/start_command.dart';
import 'package:ariami_cli/commands/stop_command.dart';
import 'package:ariami_cli/commands/status_command.dart';
import 'package:ariami_cli/commands/configure_command.dart';
import 'package:ariami_cli/commands/autostart_command.dart';
import 'package:ariami_cli/commands/reset_command.dart';
import 'package:ariami_cli/server_runner.dart';
import 'package:ariami_core/ariami_core.dart';

void main(List<String> arguments) async {
  // Check if running in server mode (background process)
  if (arguments.contains('--server-mode')) {
    // Extract port from arguments
    int port = 8080; // default
    final portIndex = arguments.indexOf('--port');
    if (portIndex != -1 && portIndex + 1 < arguments.length) {
      port = int.tryParse(arguments[portIndex + 1]) ?? 8080;
    }

    // Run server directly (background mode)
    // Retry binding with exponential backoff if port is busy
    // (handles race condition during transition from foreground to background)
    final runner = ServerRunner();
    const maxRetries = 10;
    const initialDelayMs = 100;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await runner.run(
          port: port,
          isSetupMode: false,
          isServerMode: true,
          allowPortFallback: false,
        );
        break; // Success - exit the loop
      } catch (e) {
        final isAddressInUse = e.toString().contains('Address already in use') ||
            e.toString().contains('SocketException');

        if (isAddressInUse && attempt < maxRetries) {
          // Exponential backoff: 100ms, 200ms, 400ms, 800ms, ...
          final delayMs = initialDelayMs * (1 << (attempt - 1));
          print('Port $port in use, retrying in ${delayMs}ms (attempt $attempt/$maxRetries)...');
          await Future.delayed(Duration(milliseconds: delayMs));
        } else {
          // Either not a port-in-use error, or we've exhausted retries
          print('Failed to start server: $e');
          exit(1);
        }
      }
    }
    return;
  }

  // Normal CLI mode - parse commands
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help message')
    ..addFlag('version', abbr: 'v', negatable: false, help: 'Show version')
    ..addOption('port', abbr: 'p', help: 'Server port (default: 8080)', defaultsTo: '8080')
    ..addFlag('setup', negatable: false, help: 'reset: setup/config only')
    ..addFlag('factory', negatable: false, help: 'reset: factory reset all data')
    ..addFlag('yes', abbr: 'y', negatable: false, help: 'reset: skip confirmation prompt');

  try {
    // Parse arguments
    final results = parser.parse(arguments);

    // Show help
    if (results['help'] as bool) {
      _showHelp(parser);
      return;
    }

    // Show version
    if (results['version'] as bool) {
      print('Ariami CLI version 4.4.0');
      return;
    }

    // Get command
    if (results.rest.isEmpty) {
      print('Error: No command specified.');
      print('');
      _showHelp(parser);
      exit(1);
    }

    final command = results.rest[0];
    final port = int.tryParse(results['port'] as String) ?? 8080;
    final portExplicitlyRequested = results.wasParsed('port');

    // Execute command
    switch (command) {
      case 'start':
        await StartCommand().execute(
          port: port,
          portExplicitlyRequested: portExplicitlyRequested,
        );
        break;
      case 'stop':
        await StopCommand().execute();
        break;
      case 'status':
        await StatusCommand().execute();
        break;
      case 'configure':
        await _executeConfigureCommand(results.rest);
        break;
      case 'music-folder':
        await _executeMusicFolderCommand(results.rest);
        break;
      case 'autostart':
        final action = results.rest.length > 1 ? results.rest[1] : 'status';
        await AutostartCommand().execute(action: action);
        break;
      case 'reset':
        await _executeResetCommand(
          wantsSetup: results['setup'] as bool,
          wantsFactory: results['factory'] as bool,
          skipConfirmation: results['yes'] as bool,
        );
        break;
      default:
        print('Error: Unknown command "$command"');
        print('');
        _showHelp(parser);
        exit(1);
    }
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}

Future<void> _executeConfigureCommand(List<String> args) async {
  final configureParser = ArgParser()
    ..addOption(
      'music-folder',
      help: 'Absolute path to the music library on this machine',
    );

  final parsed = configureParser.parse(args.skip(1));
  final musicFolder = parsed['music-folder'] as String?;

  if (musicFolder == null) {
    print('Error: configure requires at least one option.');
    print('');
    print('Usage: ariami_cli configure --music-folder <path>');
    exit(1);
  }

  await ConfigureCommand().execute(musicFolder: musicFolder);
}

Future<void> _executeMusicFolderCommand(List<String> args) async {
  if (args.length < 2 || args[1] != 'set') {
    print('Error: unknown music-folder subcommand.');
    print('');
    print('Usage: ariami_cli music-folder set <path>');
    exit(1);
  }

  if (args.length < 3 || args[2].trim().isEmpty) {
    print('Error: music-folder set requires a path.');
    print('');
    print('Usage: ariami_cli music-folder set <path>');
    exit(1);
  }

  await ConfigureCommand().execute(musicFolder: args[2]);
}

Future<void> _executeResetCommand({
  required bool wantsSetup,
  required bool wantsFactory,
  required bool skipConfirmation,
}) async {
  if (wantsSetup && wantsFactory) {
    print('Error: choose only one of --setup or --factory.');
    exit(1);
  }

  final scope = wantsSetup
      ? ResetScope.setupOnly
      : wantsFactory
          ? ResetScope.factoryReset
          : null;

  await ResetCommand().execute(
    scope: scope,
    skipConfirmation: skipConfirmation,
  );
}

void _showHelp(ArgParser parser) {
  print('Ariami CLI - Music streaming server for headless servers');
  print('');
  print('Usage: ariami_cli <command> [options]');
  print('');
  print('Commands:');
  print('  start       Start the Ariami server');
  print('  stop        Stop the Ariami server');
  print('  status      Show server status');
  print('  configure   Configure CLI settings');
  print('  music-folder  Manage the music library path');
  print('  autostart   Manage starting the server on boot');
  print('  reset       Reset setup or factory reset Ariami');
  print('');
  print('Options:');
  print(parser.usage);
  print('');
  print('Examples:');
  print('  ariami_cli start              # Start server on default port 8080');
  print('  ariami_cli start --port 9000  # Start server on custom port');
  print('  ariami_cli stop               # Stop the running server');
  print('  ariami_cli status             # Check server status');
  print('  ariami_cli configure --music-folder /home/user/Music');
  print('  ariami_cli music-folder set /home/user/Music');
  print('  ariami_cli autostart enable   # Start the server on boot');
  print('  ariami_cli autostart disable  # Stop starting on boot');
  print('  ariami_cli autostart status   # Show current setting');
  print('  ariami_cli reset              # Interactive reset menu');
  print('  ariami_cli reset --setup      # Reset setup/config only');
  print('  ariami_cli reset --factory -y # Factory reset without prompts');
}
