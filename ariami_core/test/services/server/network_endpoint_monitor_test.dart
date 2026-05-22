import 'dart:async';

import 'package:ariami_core/services/server/network_endpoint_monitor.dart';
import 'package:test/test.dart';

void main() {
  group('NetworkEndpointMonitor', () {
    test('notifies when discovered endpoints change', () async {
      var tailscaleIp = '100.64.10.20';
      const lanIp = '192.168.1.50';
      final changes = <NetworkEndpoints>[];

      final monitor = NetworkEndpointMonitor(
        onChanged: changes.add,
        pollInterval: const Duration(milliseconds: 20),
      );
      monitor.setDiscoveryCallback(
        () async => NetworkEndpoints(
          tailscaleIp: tailscaleIp,
          lanIp: lanIp,
        ),
      );
      monitor.start();

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(changes, hasLength(1));
      expect(changes.first.tailscaleIp, tailscaleIp);

      tailscaleIp = '100.64.10.99';
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(changes.length, greaterThanOrEqualTo(2));
      expect(changes.last.tailscaleIp, '100.64.10.99');

      monitor.stop();
    });

    test('does not notify when discovered endpoints are unchanged', () async {
      var notifyCount = 0;

      final monitor = NetworkEndpointMonitor(
        onChanged: (_) => notifyCount++,
        pollInterval: const Duration(milliseconds: 20),
      );
      monitor.setDiscoveryCallback(
        () async => const NetworkEndpoints(
          tailscaleIp: '100.64.10.20',
          lanIp: '192.168.1.50',
        ),
      );
      monitor.start();

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(notifyCount, 1);

      monitor.stop();
    });
  });
}
