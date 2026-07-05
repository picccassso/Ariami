import 'package:ariami_cli/services/startup_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StartupSummary.buildBanner', () {
    test('formats full server information', () {
      final lines = StartupSummary.buildBanner(
        version: '4.4.0',
        modeLabel: 'background',
        port: 8080,
        bindHost: '0.0.0.0',
        lanIp: '192.168.1.20',
        tailscaleIp: '100.101.102.103',
        dataDir: '/home/pi/.ariami_cli',
        musicDir: '/home/pi/Music',
        musicDirExists: true,
        accountCount: 2,
        hasOwnerAccount: true,
        setupComplete: true,
        pid: 1234,
      );

      expect(lines, [
        '──────────────────────────────────────────────────────────',
        ' Ariami Server 4.4.0',
        ' Status:    running (background, PID 1234)',
        ' Dashboard: http://192.168.1.20:8080',
        ' Local:     http://127.0.0.1:8080',
        ' Tailscale: http://100.101.102.103:8080',
        ' Data:      /home/pi/.ariami_cli',
        ' Music:     /home/pi/Music',
        ' Auth:      enabled — 2 accounts',
        ' Network:   LAN/Tailscale/VPN only. Do not expose this port to the public internet.',
        '──────────────────────────────────────────────────────────',
      ]);
    });

    test('omits network addresses when none are available', () {
      final lines = StartupSummary.buildBanner(
        version: '4.4.0',
        modeLabel: 'foreground',
        port: 8080,
        bindHost: '0.0.0.0',
        lanIp: null,
        tailscaleIp: null,
        dataDir: '/home/pi/.ariami_cli',
        musicDir: '/home/pi/Music',
        musicDirExists: true,
        accountCount: 1,
        hasOwnerAccount: true,
        setupComplete: true,
      );

      expect(lines, contains(' Status:    running (foreground)'));
      expect(lines, contains(' Local:     http://127.0.0.1:8080'));
      expect(lines.any((line) => line.startsWith(' Dashboard:')), isFalse);
      expect(lines.any((line) => line.startsWith(' Tailscale:')), isFalse);
    });

    test('shows localhost-only note and hides remote URLs', () {
      final lines = StartupSummary.buildBanner(
        version: '4.4.0',
        modeLabel: 'background',
        port: 8080,
        bindHost: '127.0.0.1',
        lanIp: '192.168.1.20',
        tailscaleIp: '100.101.102.103',
        dataDir: '/home/pi/.ariami_cli',
        musicDir: '/home/pi/Music',
        musicDirExists: true,
        accountCount: 1,
        hasOwnerAccount: true,
        setupComplete: true,
        pid: 1234,
      );

      expect(lines, contains(' Local:     http://127.0.0.1:8080'));
      expect(
        lines,
        contains(
          ' Note:      bound to localhost only — other devices cannot connect.',
        ),
      );
      expect(lines.any((line) => line.startsWith(' Dashboard:')), isFalse);
      expect(lines.any((line) => line.startsWith(' Tailscale:')), isFalse);
    });

    test('warns when there is no owner account', () {
      final lines = StartupSummary.buildBanner(
        version: '4.4.0',
        modeLabel: 'foreground',
        port: 8080,
        bindHost: '0.0.0.0',
        lanIp: null,
        tailscaleIp: null,
        dataDir: '/home/pi/.ariami_cli',
        musicDir: null,
        musicDirExists: false,
        accountCount: 0,
        hasOwnerAccount: false,
        setupComplete: true,
      );

      expect(
        lines,
        contains(
          ' Auth:      enabled — no owner account yet. Create one in the dashboard before real use.',
        ),
      );
    });

    test('shows setup incomplete status and next step', () {
      final lines = StartupSummary.buildBanner(
        version: '4.4.0',
        modeLabel: 'foreground',
        port: 8080,
        bindHost: '0.0.0.0',
        lanIp: '192.168.1.20',
        tailscaleIp: null,
        dataDir: '/home/pi/.ariami_cli',
        musicDir: null,
        musicDirExists: false,
        accountCount: 0,
        hasOwnerAccount: false,
        setupComplete: false,
      );

      expect(
        lines,
        contains(' Status:    setup required — finish setup in the browser'),
      );
      expect(
        lines,
        contains(
            ' Setup:     required — open the Dashboard URL above to continue'),
      );
    });

    test('marks missing configured music folder', () {
      final lines = StartupSummary.buildBanner(
        version: '4.4.0',
        modeLabel: 'foreground',
        port: 8080,
        bindHost: '0.0.0.0',
        lanIp: null,
        tailscaleIp: null,
        dataDir: '/home/pi/.ariami_cli',
        musicDir: '/mnt/music',
        musicDirExists: false,
        accountCount: 1,
        hasOwnerAccount: true,
        setupComplete: true,
      );

      expect(lines, contains(' Music:     /mnt/music (folder missing!)'));
    });
  });
}
