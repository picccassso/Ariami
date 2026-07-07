import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import 'package:ariami_cli/commands/start_command.dart';
import 'package:ariami_cli/commands/stop_command.dart';
import 'package:ariami_cli/commands/status_command.dart';
import 'package:ariami_cli/commands/configure_command.dart';
import 'package:ariami_cli/commands/autostart_command.dart';
import 'package:ariami_cli/commands/reset_command.dart';
import 'package:ariami_cli/server_runner.dart';
import 'package:ariami_cli/services/cli_state_service.dart';
import 'package:ariami_core/ariami_core.dart';

void main(List<String> arguments) {
  // The Dart VM ignores SIGPIPE, so when a downstream pipe reader such as
  // `head` exits early, stdout writes fail with an EPIPE FileSystemException
  // delivered as an *uncaught async* error — no try/catch around the write
  // sees it. Treat that as the normal end of a pipeline, not a crash, so
  // `ariami_cli status | head` composes cleanly in scripts.
  runZonedGuarded(
    () => _run(arguments),
    (error, stackTrace) {
      if (_isBrokenPipe(error)) exit(0);
      _reportFatal(error, stackTrace,
          verbose: arguments.contains('--verbose'));
    },
  );
}

bool _isBrokenPipe(Object error) {
  if (error is! FileSystemException) return false;
  final code = error.osError?.errorCode;
  // POSIX EPIPE; Windows ERROR_BROKEN_PIPE / ERROR_NO_DATA.
  return code == 32 || code == 109 || code == 232;
}

Never _reportFatal(Object error, StackTrace stackTrace,
    {required bool verbose}) {
  try {
    stderr.writeln('ERROR: $error');
    if (verbose) {
      stderr.writeln('Stack trace: $stackTrace');
    }
  } catch (_) {
    // stderr may be a broken pipe too; the exit code still reports failure.
  }
  exit(1);
}

Future<void> _run(List<String> arguments) async {
  // Normal CLI mode - parse commands
  final parser = ArgParser(allowTrailingOptions: false)
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help message')
    ..addFlag('version', abbr: 'v', negatable: false, help: 'Show version')
    ..addOption('port',
        abbr: 'p', help: 'Server port (default: 8080)', defaultsTo: '8080')
    ..addOption('host',
        help: 'HTTP bind address (default: 0.0.0.0)', defaultsTo: '0.0.0.0')
    ..addFlag('no-browser',
        negatable: false,
        help: 'During setup, print URLs and never auto-open a browser')
    ..addFlag('verbose',
        negatable: false, help: 'Show stack traces and extra debug output')
    ..addFlag('server-mode', negatable: false, hide: true)
    ..addFlag('setup', negatable: false, help: 'reset: setup/config only')
    ..addFlag('factory',
        negatable: false, help: 'reset: factory reset all data')
    ..addFlag('yes',
        abbr: 'y', negatable: false, help: 'reset: skip confirmation prompt');

  try {
    // Parse arguments
    final results = parser.parse(arguments);

    if (results['server-mode'] as bool) {
      await _executeServerMode(results);
      return;
    }

    // Show help
    if (results['help'] as bool) {
      _showHelp(parser);
      return;
    }

    // Show version
    if (results['version'] as bool) {
      print('Ariami CLI version $kAriamiVersion');
      return;
    }

    // Get command
    if (results.rest.isEmpty) {
      _usageError(parser, 'No command specified.');
    }

    final command = results.rest[0];
    // Execute command
    switch (command) {
      case 'start':
        await _executeStartCommand(results);
        break;
      case 'stop':
        _rejectTrailingFlags(parser, results);
        await StopCommand().execute();
        break;
      case 'status':
        _rejectTrailingFlags(parser, results);
        await StatusCommand().execute();
        break;
      case 'configure':
        await _executeConfigureCommand(results.rest);
        break;
      case 'music-folder':
        await _executeMusicFolderCommand(results.rest);
        break;
      case 'autostart':
        _rejectTrailingFlags(parser, results);
        final action = results.rest.length > 1 ? results.rest[1] : 'status';
        await AutostartCommand().execute(action: action);
        break;
      case 'reset':
        await _executeResetCommand(results);
        break;
      default:
        _usageError(parser, 'Unknown command "$command"');
    }
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('');
    _showHelp(parser, output: stderr);
    exit(2);
  } catch (e, stackTrace) {
    if (_isBrokenPipe(e)) exit(0);
    _reportFatal(e, stackTrace, verbose: arguments.contains('--verbose'));
  }
}

Future<void> _executeStartCommand(ArgResults globalResults) async {
  final startParser = ArgParser()
    ..addOption(
      'port',
      abbr: 'p',
      help: 'Server port (default: 8080)',
      defaultsTo: globalResults['port'] as String,
    )
    ..addOption(
      'host',
      help: 'HTTP bind address (default: 0.0.0.0)',
      defaultsTo: globalResults['host'] as String,
    )
    ..addFlag(
      'no-browser',
      negatable: false,
      help: 'During setup, print URLs and never auto-open a browser',
    )
    ..addFlag(
      'verbose',
      negatable: false,
      help: 'Show stack traces and extra debug output',
    );
  final startResults = startParser.parse(globalResults.rest.skip(1));
  final port = int.tryParse(startResults['port'] as String) ?? 8080;

  await StartCommand().execute(
    port: port,
    portExplicitlyRequested:
        globalResults.wasParsed('port') || startResults.wasParsed('port'),
    bindHost: startResults['host'] as String,
    bindHostExplicitlyRequested:
        globalResults.wasParsed('host') || startResults.wasParsed('host'),
    noBrowser: (globalResults['no-browser'] as bool) ||
        (startResults['no-browser'] as bool),
    verbose:
        (globalResults['verbose'] as bool) || (startResults['verbose'] as bool),
  );
}

Future<void> _executeServerMode(ArgResults results) async {
  final port = int.tryParse(results['port'] as String) ?? 8080;
  final verbose = results['verbose'] as bool;

  if (results.wasParsed('host')) {
    await CliStateService().setBindHost(results['host'] as String);
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
        verbose: verbose,
      );
      break; // Success - exit the loop
    } catch (e) {
      if (ServerPortPolicy.isAddressInUseError(e) && attempt < maxRetries) {
        // Exponential backoff: 100ms, 200ms, 400ms, 800ms, ...
        final delayMs = initialDelayMs * (1 << (attempt - 1));
        print(
          'Port $port in use, retrying in ${delayMs}ms '
          '(attempt $attempt/$maxRetries)...',
        );
        await Future.delayed(Duration(milliseconds: delayMs));
      } else {
        // ServerRunner already reported the failure to stderr.
        exit(1);
      }
    }
  }

  // The server loop returned after a graceful shutdown. Native resources
  // (sqlite, FFI isolates) can keep the VM alive, so exit explicitly now
  // that cleanup has completed.
  exit(0);
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
    stderr.writeln('Error: configure requires at least one option.');
    stderr.writeln('');
    stderr.writeln('Usage: ariami_cli configure --music-folder <path>');
    exit(2);
  }

  await ConfigureCommand().execute(musicFolder: musicFolder);
}

Future<void> _executeMusicFolderCommand(List<String> args) async {
  if (args.length < 2 || args[1] != 'set') {
    stderr.writeln('Error: unknown music-folder subcommand.');
    stderr.writeln('');
    stderr.writeln('Usage: ariami_cli music-folder set <path>');
    exit(2);
  }

  if (args.length < 3 || args[2].trim().isEmpty) {
    stderr.writeln('Error: music-folder set requires a path.');
    stderr.writeln('');
    stderr.writeln('Usage: ariami_cli music-folder set <path>');
    exit(2);
  }

  await ConfigureCommand().execute(musicFolder: args[2]);
}

Future<void> _executeResetCommand(ArgResults globalResults) async {
  final resetParser = ArgParser()
    ..addFlag('setup', negatable: false, help: 'reset: setup/config only')
    ..addFlag('factory',
        negatable: false, help: 'reset: factory reset all data')
    ..addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'reset: skip confirmation prompt',
    );
  final resetResults = resetParser.parse(globalResults.rest.skip(1));
  final wantsSetup =
      (globalResults['setup'] as bool) || (resetResults['setup'] as bool);
  final wantsFactory =
      (globalResults['factory'] as bool) || (resetResults['factory'] as bool);
  final skipConfirmation =
      (globalResults['yes'] as bool) || (resetResults['yes'] as bool);

  if (wantsSetup && wantsFactory) {
    stderr.writeln('Error: choose only one of --setup or --factory.');
    exit(2);
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

void _usageError(ArgParser parser, String message) {
  stderr.writeln('Error: $message');
  stderr.writeln('');
  _showHelp(parser, output: stderr);
  exit(2);
}

void _rejectTrailingFlags(ArgParser parser, ArgResults results) {
  for (final arg in results.rest.skip(1)) {
    if (arg.startsWith('-')) {
      _usageError(
          parser, 'Unknown option "$arg" for command "${results.rest[0]}"');
    }
  }
}

void _showHelp(ArgParser parser, {IOSink? output}) {
  final out = output ?? stdout;
  out.writeln('Ariami CLI - Music streaming server for headless servers');
  out.writeln('');
  out.writeln('Usage: ariami_cli <command> [options]');
  out.writeln('');
  out.writeln('Commands:');
  out.writeln('  start       Start the Ariami server');
  out.writeln('  stop        Stop the Ariami server');
  out.writeln('  status      Show server status');
  out.writeln('  configure   Configure CLI settings');
  out.writeln('  music-folder  Manage the music library path');
  out.writeln('  autostart   Manage starting the server on boot');
  out.writeln('  reset       Reset setup or factory reset Ariami');
  out.writeln('');
  out.writeln('Options:');
  out.writeln(parser.usage);
  out.writeln('');
  out.writeln('Examples:');
  out.writeln(
      '  ariami_cli start              # Start server on default port 8080');
  out.writeln('  ariami_cli start --port 9000  # Start server on custom port');
  out.writeln(
      '  ariami_cli start --no-browser # Print setup URLs without opening a browser');
  out.writeln('  ariami_cli start --host 127.0.0.1');
  out.writeln('  ariami_cli stop               # Stop the running server');
  out.writeln('  ariami_cli status             # Check server status');
  out.writeln('  ariami_cli configure --music-folder /home/user/Music');
  out.writeln('  ariami_cli music-folder set /home/user/Music');
  out.writeln('  ariami_cli autostart enable   # Start the server on boot');
  out.writeln('  ariami_cli autostart disable  # Stop starting on boot');
  out.writeln('  ariami_cli autostart status   # Show current setting');
  out.writeln('  ariami_cli reset              # Interactive reset menu');
  out.writeln('  ariami_cli reset --setup      # Reset setup/config only');
  out.writeln(
      '  ariami_cli reset --factory -y # Factory reset without prompts');
}
