import 'dart:io';
import 'package:args/args.dart';
import 'package:bma_cli/commands/start_command.dart';
import 'package:bma_cli/commands/stop_command.dart';
import 'package:bma_cli/commands/status_command.dart';
import 'package:bma_cli/server_runner.dart';

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
    final runner = ServerRunner();
    await runner.run(port: port, isSetupMode: false);
    return;
  }

  // Normal CLI mode - parse commands
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help message')
    ..addFlag('version', abbr: 'v', negatable: false, help: 'Show version')
    ..addOption('port', abbr: 'p', help: 'Server port (default: 8080)', defaultsTo: '8080');

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
      print('BMA CLI version 1.0.0');
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

    // Execute command
    switch (command) {
      case 'start':
        await StartCommand().execute(port: port);
        break;
      case 'stop':
        await StopCommand().execute();
        break;
      case 'status':
        await StatusCommand().execute();
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

void _showHelp(ArgParser parser) {
  print('BMA CLI - Basic Music App for headless servers');
  print('');
  print('Usage: bma_cli <command> [options]');
  print('');
  print('Commands:');
  print('  start       Start the BMA server');
  print('  stop        Stop the BMA server');
  print('  status      Show server status');
  print('');
  print('Options:');
  print(parser.usage);
  print('');
  print('Examples:');
  print('  bma_cli start              # Start server on default port 8080');
  print('  bma_cli start --port 9000  # Start server on custom port');
  print('  bma_cli stop               # Stop the running server');
  print('  bma_cli status             # Check server status');
}
