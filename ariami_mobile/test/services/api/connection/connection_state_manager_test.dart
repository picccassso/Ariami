import 'package:flutter_test/flutter_test.dart';
import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/services/api/connection/connection_state_manager.dart';

void main() {
  group('ConnectionStateManager', () {
    late ConnectionStateManager manager;

    setUp(() {
      manager = ConnectionStateManager();
    });

    tearDown(() {
      manager.dispose();
    });

    group('Initial State', () {
      test('should start with isConnected as false', () {
        expect(manager.isConnected, isFalse);
      });

      test('should start with isManuallyDisconnected as false', () {
        expect(manager.isManuallyDisconnected, isFalse);
      });

      test('should start with null serverInfo', () {
        expect(manager.serverInfo, isNull);
      });

      test('should start with hasServerInfo as false', () {
        expect(manager.hasServerInfo, isFalse);
      });

      test('should start with null restore failure info', () {
        expect(manager.lastRestoreFailureCode, isNull);
        expect(manager.lastRestoreFailureMessage, isNull);
        expect(manager.lastRestoreFailureDetails, isNull);
        expect(manager.didLastRestoreFailForAuth, isFalse);
      });
    });

    group('Connection State Management', () {
      test('setConnected should update isConnected', () {
        manager.setConnected(true);
        expect(manager.isConnected, isTrue);

        manager.setConnected(false);
        expect(manager.isConnected, isFalse);
      });

      test('setManuallyDisconnected should update state', () {
        manager.setManuallyDisconnected(true);
        expect(manager.isManuallyDisconnected, isTrue);

        manager.setManuallyDisconnected(false);
        expect(manager.isManuallyDisconnected, isFalse);
      });

      test('resetConnectionState should reset connection flags', () {
        manager.setConnected(true);
        manager.setManuallyDisconnected(true);

        manager.resetConnectionState();

        expect(manager.isConnected, isFalse);
        expect(manager.isManuallyDisconnected, isFalse);
      });

      test('resetConnectionState should preserve serverInfo', () {
        final serverInfo = _createTestServerInfo();
        manager.setServerInfo(serverInfo);

        manager.resetConnectionState();

        expect(manager.serverInfo, equals(serverInfo));
      });
    });

    group('Server Info Management', () {
      test('setServerInfo should update serverInfo', () {
        final serverInfo = _createTestServerInfo();
        manager.setServerInfo(serverInfo);

        expect(manager.serverInfo, equals(serverInfo));
        expect(manager.hasServerInfo, isTrue);
      });

      test('setServerInfo with null should clear serverInfo', () {
        final serverInfo = _createTestServerInfo();
        manager.setServerInfo(serverInfo);
        expect(manager.hasServerInfo, isTrue);

        manager.setServerInfo(null);
        expect(manager.serverInfo, isNull);
        expect(manager.hasServerInfo, isFalse);
      });

      test('updateServerIp should update the server IP', () {
        final serverInfo = _createTestServerInfo(ip: '192.168.1.1');
        manager.setServerInfo(serverInfo);

        manager.updateServerIp('10.0.0.1');

        expect(manager.serverInfo?.server, equals('10.0.0.1'));
        expect(manager.serverInfo?.lanServer, equals(serverInfo.lanServer));
        expect(manager.serverInfo?.port, equals(serverInfo.port));
      });

      test('updateServerIp should not change if IP is the same', () {
        final serverInfo = _createTestServerInfo(ip: '192.168.1.1');
        manager.setServerInfo(serverInfo);

        // This should be a no-op
        manager.updateServerIp('192.168.1.1');

        expect(manager.serverInfo?.server, equals('192.168.1.1'));
      });

      test('updateServerIp should do nothing if serverInfo is null', () {
        // Should not throw
        manager.updateServerIp('10.0.0.1');
        expect(manager.serverInfo, isNull);
      });
    });

    group('Restore Failure Tracking', () {
      test('setRestoreFailure should record failure info', () {
        manager.setRestoreFailure(
          code: 'SERVER_ERROR',
          message: 'Connection refused',
          details: {'port': 8080},
        );

        expect(manager.lastRestoreFailureCode, equals('SERVER_ERROR'));
        expect(manager.lastRestoreFailureMessage, equals('Connection refused'));
        expect(manager.lastRestoreFailureDetails, equals({'port': 8080}));
      });

      test('setRestoreFailure without details should work', () {
        manager.setRestoreFailure(
          code: 'TIMEOUT',
          message: 'Request timed out',
        );

        expect(manager.lastRestoreFailureCode, equals('TIMEOUT'));
        expect(manager.lastRestoreFailureMessage, equals('Request timed out'));
        expect(manager.lastRestoreFailureDetails, isNull);
      });

      test('clearRestoreFailure should clear all failure info', () {
        manager.setRestoreFailure(
          code: 'ERROR',
          message: 'Something went wrong',
          details: {},
        );

        manager.clearRestoreFailure();

        expect(manager.lastRestoreFailureCode, isNull);
        expect(manager.lastRestoreFailureMessage, isNull);
        expect(manager.lastRestoreFailureDetails, isNull);
      });

      group('didLastRestoreFailForAuth', () {
        test('should be true for AUTH_REQUIRED code', () {
          manager.setRestoreFailure(
            code: 'AUTH_REQUIRED',
            message: 'Authentication required',
          );
          expect(manager.didLastRestoreFailForAuth, isTrue);
        });

        test('should be true for SESSION_EXPIRED code', () {
          manager.setRestoreFailure(
            code: 'SESSION_EXPIRED',
            message: 'Session expired',
          );
          expect(manager.didLastRestoreFailForAuth, isTrue);
        });

        test('should be false for other codes', () {
          manager.setRestoreFailure(
            code: 'SERVER_ERROR',
            message: 'Server error',
          );
          expect(manager.didLastRestoreFailForAuth, isFalse);
        });

        test('should be false when no failure recorded', () {
          expect(manager.didLastRestoreFailForAuth, isFalse);
        });
      });
    });

    group('Connection State Stream', () {
      test('should emit events when connection state changes', () async {
        final events = <bool>[];
        final subscription = manager.connectionStateStream.listen(events.add);

        manager.setConnected(true);
        manager.setConnected(false);
        manager.setConnected(true);

        // Wait for events to propagate
        await Future<void>.delayed(Duration.zero);

        expect(events, equals([true, false, true]));
        await subscription.cancel();
      });

      test('should not emit when setting same value', () async {
        final events = <bool>[];
        final subscription = manager.connectionStateStream.listen(events.add);

        manager.setConnected(true);
        manager.setConnected(true); // Duplicate
        manager.setConnected(true); // Duplicate again

        await Future<void>.delayed(Duration.zero);

        expect(events, equals([true]));
        await subscription.cancel();
      });

      test('should support multiple listeners', () async {
        final events1 = <bool>[];
        final events2 = <bool>[];

        final sub1 = manager.connectionStateStream.listen(events1.add);
        final sub2 = manager.connectionStateStream.listen(events2.add);

        manager.setConnected(true);
        await Future<void>.delayed(Duration.zero);

        expect(events1, equals([true]));
        expect(events2, equals([true]));

        await sub1.cancel();
        await sub2.cancel();
      });
    });

    group('Server Info Stream', () {
      test('should emit events when server info changes', () async {
        final events = <ServerInfo?>[];
        final subscription = manager.serverInfoStream.listen(events.add);

        final server1 = _createTestServerInfo(ip: '192.168.1.1');
        final server2 = _createTestServerInfo(ip: '10.0.0.1');

        manager.setServerInfo(server1);
        manager.setServerInfo(server2);
        manager.setServerInfo(null);

        await Future<void>.delayed(Duration.zero);

        expect(events.length, equals(3));
        expect(events[0]?.server, equals('192.168.1.1'));
        expect(events[1]?.server, equals('10.0.0.1'));
        expect(events[2], isNull);

        await subscription.cancel();
      });

      test('should emit even when setting same server info reference',
          () async {
        final events = <ServerInfo?>[];
        final subscription = manager.serverInfoStream.listen(events.add);

        final server = _createTestServerInfo();
        manager.setServerInfo(server);
        manager.setServerInfo(server); // Same reference

        await Future<void>.delayed(Duration.zero);

        // Should emit twice because we don't check for equality
        expect(events.length, equals(2));

        await subscription.cancel();
      });
    });

    group('Combined Scenarios', () {
      test('full connection lifecycle', () async {
        final connectionEvents = <bool>[];
        final serverEvents = <ServerInfo?>[];

        final connSub =
            manager.connectionStateStream.listen(connectionEvents.add);
        final serverSub = manager.serverInfoStream.listen(serverEvents.add);

        // Initial state
        expect(manager.isConnected, isFalse);
        expect(manager.hasServerInfo, isFalse);

        // Connect
        final serverInfo = _createTestServerInfo();
        manager.setServerInfo(serverInfo);
        manager.setConnected(true);

        await Future<void>.delayed(Duration.zero);

        expect(manager.isConnected, isTrue);
        expect(manager.hasServerInfo, isTrue);
        expect(connectionEvents, equals([true]));
        expect(serverEvents.length, equals(1));

        // Disconnect
        manager.setConnected(false);
        manager.setManuallyDisconnected(true);

        await Future<void>.delayed(Duration.zero);

        expect(manager.isConnected, isFalse);
        expect(manager.isManuallyDisconnected, isTrue);
        expect(connectionEvents, equals([true, false]));

        // Server info should be preserved
        expect(manager.serverInfo, equals(serverInfo));

        await connSub.cancel();
        await serverSub.cancel();
      });

      test('failed reconnection attempt flow', () {
        // Simulate a failed reconnect
        manager.setRestoreFailure(
          code: 'SERVER_ERROR',
          message: 'Server unreachable',
        );
        expect(manager.lastRestoreFailureCode, equals('SERVER_ERROR'));

        // Clear and try again
        manager.clearRestoreFailure();
        expect(manager.lastRestoreFailureCode, isNull);

        // Auth failure
        manager.setRestoreFailure(
          code: 'SESSION_EXPIRED',
          message: 'Session expired',
        );
        expect(manager.didLastRestoreFailForAuth, isTrue);
      });
    });
  });
}

ServerInfo _createTestServerInfo({String ip = '192.168.1.100'}) {
  return ServerInfo(
    server: ip,
    port: 8080,
    name: 'Test Server',
    version: '3.2.0',
    lanServer: '10.0.0.50',
    tailscaleServer: '100.64.0.1',
    authRequired: true,
    legacyMode: false,
  );
}
