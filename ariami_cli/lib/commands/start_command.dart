import 'dart:async';
import 'dart:io';
import '../services/daemon_service.dart';
import '../services/cli_state_service.dart';
import '../services/cli_guidance.dart';
import '../services/cli_status_info.dart';
import '../services/browser_service.dart';
import '../services/cli_tailscale_service.dart';
import '../services/web_assets_resolver.dart';
import '../services/autostart_service.dart';
import '../services/startup_summary.dart';
import '../server_runner.dart';
import 'package:ariami_core/ariami_core.dart';

/// Command to start the Ariami CLI server
class StartCommand {
  final DaemonService _daemonService = DaemonService();
  final CliStateService _stateService = CliStateService();
  final BrowserService _browserService = BrowserService();
  final WebAssetsResolver _webAssetsResolver = WebAssetsResolver();
  final CliTailscaleService _tailscaleService = CliTailscaleService();
  final AutostartService _autostartService = AutostartService();

  /// Execute the start command
  Future<void> execute({
    int port = 8080,
    bool portExplicitlyRequested = false,
    String bindHost = '0.0.0.0',
    bool bindHostExplicitlyRequested = false,
    bool noBrowser = false,
    bool verbose = false,
  }) async {
    if (bindHostExplicitlyRequested) {
      await _stateService.setBindHost(bindHost);
    }

    // Check if already running
    if (await _daemonService.isRunning()) {
      print('Ariami CLI server is already running.');
      print(
        'Use "ariami_cli status" to check status or "ariami_cli stop" to stop it.',
      );
      return;
    }

    final webAssets = await _webAssetsResolver.resolve();
    if (!webAssets.found) {
      _webAssetsResolver.printNotFoundError(webAssets);
      return;
    }

    // Check if this is first-time setup
    final isSetupComplete = await _stateService.isSetupComplete();
    final savedPort = await _stateService.getServerPort();
    final preferredPort = portExplicitlyRequested ? port : (savedPort ?? port);
    final allowPortFallback = !portExplicitlyRequested;
    final activeBindHost = await _stateService.getBindHost();

    if (!isSetupComplete) {
      // Ask about starting on boot before anything else launches.
      await _promptAndConfigureAutostart();

      _writeSetupLine('Starting Ariami setup...');
      for (final line in CliGuidance.firstRunIntro) {
        _writeSetupLine(line);
      }
      _writeSetupLine('');

      // Run server in foreground (setup mode)
      final runner = ServerRunner();
      try {
        await runZoned(
          () => runner.run(
            port: preferredPort,
            isSetupMode: true,
            allowPortFallback: allowPortFallback,
            verbose: verbose,
            onHttpServerReady: (readyPort) => _openSetupBrowser(
              readyPort,
              noBrowser: noBrowser,
            ),
          ),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) {
              if (_shouldShowQuietSetupLog(line, verbose: verbose)) {
                parent.print(zone, line);
              }
            },
          ),
        );
      } catch (_) {
        // ServerRunner already reported the failure to stderr.
        exit(1);
      }

      // Reaching here means the setup server shut down gracefully (signal)
      // without transitioning to the background daemon. Native resources
      // (sqlite, FFI isolates) can keep the VM alive, so exit explicitly
      // now that cleanup has completed.
      exit(0);
    } else {
      print('Starting Ariami CLI server in background...');
      print('');

      final daemonPort = savedPort ?? preferredPort;

      // Start server in background with --server-mode flag
      final pid = await _daemonService.startServerInBackground([
        '--server-mode',
        '--port',
        daemonPort.toString(),
        '--host',
        activeBindHost,
        if (verbose) '--verbose',
      ]);

      if (pid == null) {
        print('ERROR: Failed to start server in background.');
        print('Check logs for details.');
        exit(1);
      }

      // Save server state
      await _daemonService.saveServerState({
        'port': daemonPort,
        'pid': pid,
        'host': activeBindHost,
        'started_at': DateTime.now().toIso8601String(),
      });

      print('✓ Ariami CLI server started successfully!');
      print('');
      await _printBackgroundStartSummary(
        port: daemonPort,
        pid: pid,
        bindHost: activeBindHost,
      );
      print('');
      print('Use "ariami_cli status" to check server status');
      print('Use "ariami_cli stop" to stop the server');
      print('');
    }
  }

  /// Ask the user whether Ariami should start automatically on boot, and apply
  /// their choice. Runs before the setup server/browser launches.
  Future<void> _promptAndConfigureAutostart() async {
    if (!stdin.hasTerminal) {
      _writeSetupLine(
        'Non-interactive session: skipping the start-on-boot prompt. Use '
        '"ariami_cli autostart enable" to turn it on.',
      );
      _writeSetupLine('');
      return;
    }

    if (!_autostartService.isSupported) {
      return;
    }

    stdout.write(
      'Start Ariami automatically on boot (after restart, etc.)? [y/N]: ',
    );
    // On macOS stdin.hasTerminal can report true for /dev/null, so a null
    // read (EOF) is the reliable non-interactive signal: skip without
    // touching the existing autostart setting.
    final rawAnswer = stdin.readLineSync();
    if (rawAnswer == null) {
      _writeSetupLine('');
      _writeSetupLine(
        'Non-interactive session: skipping the start-on-boot prompt. Use '
        '"ariami_cli autostart enable" to turn it on.',
      );
      _writeSetupLine('');
      return;
    }
    final answer = rawAnswer.trim().toLowerCase();
    final wantsAutostart = answer == 'y' || answer == 'yes';

    if (wantsAutostart) {
      final ok = await _autostartService.enable();
      _writeSetupLine(
        ok
            ? '✓ Ariami will start automatically on boot.'
            : 'Could not configure start-on-boot. Continuing setup.',
      );
    } else {
      // Make sure any previous autostart entry is removed.
      await _autostartService.disable();
      _writeSetupLine('Ariami will not start automatically on boot.');
    }
    _writeSetupLine('');
  }

  Future<void> _openSetupBrowser(int port, {required bool noBrowser}) async {
    await _printSetupReadyUrls(port);

    if (noBrowser) {
      _writeSetupLine('Browser auto-open is disabled.');
      _writeSetupLine(
          'Open one of the addresses above manually to continue setup.');
      return;
    }

    final opened = await _browserService.openAriamiInterface(port: port);
    if (!opened) {
      _writeSetupLine('');
      _writeSetupLine('Your browser did not open automatically.');
      _writeSetupLine('Open one of the addresses above to continue setup.');
    }
  }

  Future<void> _printSetupReadyUrls(int port) async {
    final lanIp = await _tailscaleService.getLanIp();
    final tailscaleIp = await _tailscaleService.getTailscaleIp();

    _writeSetupLine('Ariami setup is ready.');
    _writeSetupLine('');
    _writeSetupLine('Open setup:');
    _writeSetupLine('  This machine:  http://localhost:$port');

    if (lanIp != null) {
      _writeSetupLine('  Same network:  http://$lanIp:$port');
    }

    if (tailscaleIp != null) {
      _writeSetupLine('  Tailscale:     http://$tailscaleIp:$port');
      _writeSetupLine('');
      _writeSetupLine(
        'Use the Tailscale address from devices signed into Tailscale.',
      );
    } else {
      _writeSetupLine('');
      _writeSetupLine(
        'No Tailscale address was detected. You can enable it later for remote access.',
      );
    }

    _writeSetupLine('Keep this terminal open until setup finishes.');
    _writeSetupLine('');
    for (final line in CliGuidance.setupNextSteps) {
      _writeSetupLine(line);
    }
    _writeSetupLine(
      'Network:   keep Ariami on LAN/Tailscale/VPN. Do not expose this port to the public internet.',
    );
    _writeSetupLine('');
  }

  Future<void> _printBackgroundStartSummary({
    required int port,
    required int pid,
    required String bindHost,
  }) async {
    final lanIp = await _tailscaleService.getLanIp();
    final tailscaleIp = await _tailscaleService.getTailscaleIp();
    final musicDir = await _stateService.getMusicFolderPath();
    final musicDirExists = musicDir != null &&
        musicDir.isNotEmpty &&
        await Directory(musicDir).exists();
    final auth = await readAuthSummary();
    final setupComplete = await _stateService.isSetupComplete();

    for (final line in StartupSummary.buildBanner(
      version: kAriamiVersion,
      modeLabel: 'background',
      port: port,
      bindHost: bindHost,
      lanIp: lanIp,
      tailscaleIp: tailscaleIp,
      dataDir: CliStateService.getConfigDir(),
      musicDir: musicDir,
      musicDirExists: musicDirExists,
      accountCount: auth.accountCount,
      hasOwnerAccount: auth.hasOwnerAccount,
      setupComplete: setupComplete,
      pid: pid,
    )) {
      print(line);
    }
  }

  bool _shouldShowQuietSetupLog(String line, {required bool verbose}) {
    return verbose ||
        line.startsWith('ERROR:') ||
        line.startsWith('Error:') ||
        line.startsWith('Failed to start server:') ||
        line.startsWith('Received SIG') ||
        line.startsWith('Shutting down Ariami server') ||
        line.startsWith('✓ Server shutdown complete') ||
        line.startsWith('Warning: Error during shutdown:');
  }

  void _writeSetupLine(String line) {
    stdout.writeln(line);
  }
}
