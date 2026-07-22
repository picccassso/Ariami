import 'package:ariami_cli/services/server_status_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerStatusService.formatStatus', () {
    test('formats running and reachable server', () {
      final lines = ServerStatusService.formatStatus(_snapshot(
        isRunning: true,
        isReachable: true,
        pid: 1234,
        uptime: const Duration(hours: 3, minutes: 12),
        lanIp: '192.168.1.20',
        tailscaleIp: '100.101.102.103',
        accountCount: 2,
        hasOwnerAccount: true,
      ));

      expect(lines, [
        'Ariami CLI 5.0.0',
        'Server:    running (PID 1234, up 3h 12m)',
        'Reachable: yes — dashboard responding on port 8080',
        'Dashboard: http://192.168.1.20:8080',
        'Local:     http://127.0.0.1:8080',
        'Tailscale: http://100.101.102.103:8080',
        'Setup:     complete',
        'Music:     /home/pi/Music',
        'Auth:      enabled — 2 accounts',
        'Data:      /home/pi/.ariami_cli',
        '  Config:    config.json',
        '  Database:  catalog.db, metadata_cache.json',
        '  Caches:    artwork_cache/, transcoded_cache/',
        'Backup:    back up the data directory above. Your music files live '
            'separately in the music folder.',
      ]);
    });

    test('formats stopped server', () {
      final lines = ServerStatusService.formatStatus(_snapshot(
        isRunning: false,
        isReachable: false,
        accountCount: 1,
        hasOwnerAccount: true,
      ));

      expect(lines, contains('Server:    stopped'));
      expect(lines, contains('Start it with: ariami_cli start'));
      expect(lines.any((line) => line.startsWith('Reachable:')), isFalse);
      expect(lines.any((line) => line.startsWith('Dashboard:')), isFalse);
      expect(lines.any((line) => line.startsWith('Local:')), isFalse);
      expect(lines.any((line) => line.startsWith('Tailscale:')), isFalse);
    });

    test('formats running server when HTTP health check fails', () {
      final lines = ServerStatusService.formatStatus(_snapshot(
        isRunning: true,
        isReachable: false,
        pid: 1234,
        accountCount: 1,
        hasOwnerAccount: true,
      ));

      expect(
        lines,
        contains(
          'Reachable: NO — process is running but the dashboard did not '
          'respond on port 8080. Try "ariami_cli stop" then '
          '"ariami_cli start".',
        ),
      );
      expect(lines.any((line) => line.startsWith('Dashboard:')), isFalse);
      expect(lines, contains('Local:     http://127.0.0.1:8080'));
    });

    test('formats missing owner account', () {
      final lines = ServerStatusService.formatStatus(_snapshot(
        isRunning: true,
        isReachable: true,
        accountCount: 0,
        hasOwnerAccount: false,
      ));

      expect(
        lines,
        contains(
          'Auth:      enabled — no owner account yet. Create one in the '
          'dashboard.',
        ),
      );
    });

    test('formats missing music folder', () {
      final lines = ServerStatusService.formatStatus(_snapshot(
        isRunning: true,
        isReachable: true,
        musicFolderExists: false,
        accountCount: 1,
        hasOwnerAccount: true,
      ));

      expect(lines, contains('Music:     /home/pi/Music (folder missing!)'));
    });

    test('formats version mismatch', () {
      final lines = ServerStatusService.formatStatus(_snapshot(
        isRunning: true,
        isReachable: true,
        serverVersion: '4.9.0',
        accountCount: 1,
        hasOwnerAccount: true,
      ));

      expect(
        lines,
        contains('Version:   server reports 4.9.0 (CLI is 5.0.0)'),
      );
    });
  });
}

StatusSnapshot _snapshot({
  required bool isRunning,
  required bool isReachable,
  int? pid,
  Duration? uptime,
  String? serverVersion,
  String? lanIp,
  String? tailscaleIp,
  bool setupComplete = true,
  String? musicFolderPath = '/home/pi/Music',
  bool? musicFolderExists = true,
  int? accountCount,
  bool? hasOwnerAccount,
}) {
  return StatusSnapshot(
    cliVersion: '5.0.0',
    isRunning: isRunning,
    pid: pid,
    uptime: uptime,
    port: 8080,
    isReachable: isReachable,
    serverVersion: serverVersion,
    lanIp: lanIp,
    tailscaleIp: tailscaleIp,
    setupComplete: setupComplete,
    musicFolderPath: musicFolderPath,
    musicFolderExists: musicFolderExists,
    accountCount: accountCount,
    hasOwnerAccount: hasOwnerAccount,
    dataDir: '/home/pi/.ariami_cli',
    configFilePath: '/home/pi/.ariami_cli/config.json',
    catalogDbFilePath: '/home/pi/.ariami_cli/catalog.db',
    metadataCacheFilePath: '/home/pi/.ariami_cli/metadata_cache.json',
    artworkCacheDirPath: '/home/pi/.ariami_cli/artwork_cache',
    transcodedCacheDirPath: '/home/pi/.ariami_cli/transcoded_cache',
  );
}
