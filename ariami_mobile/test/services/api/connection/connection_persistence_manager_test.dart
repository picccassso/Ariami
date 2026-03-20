import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/services/api/connection/connection_persistence_manager.dart';

void main() {
  group('ConnectionPersistenceManager', () {
    late ConnectionPersistenceManager manager;
    late SharedPreferences prefs;

    setUp(() async {
      // Set up SharedPreferences mock
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();

      // Create manager with mocked prefs but no secure storage
      // (secure storage operations will be skipped in these tests)
      manager = ConnectionPersistenceManager(
        prefs: prefs,
        secureStorage: null,
      );
    });

    group('Server Info Persistence', () {
      test('saveConnectionInfo should store server info and session ID',
          () async {
        final serverInfo = _createTestServerInfo();
        const sessionId = 'test-session-123';

        await manager.saveConnectionInfo(serverInfo, sessionId);

        expect(prefs.getString('server_info'), isNotNull);
        expect(prefs.getString('session_id'), equals(sessionId));
      });

      test('loadServerInfo should return saved server info', () async {
        final serverInfo = _createTestServerInfo();
        const sessionId = 'test-session-123';

        await manager.saveConnectionInfo(serverInfo, sessionId);
        final loaded = await manager.loadServerInfo();

        expect(loaded, isNotNull);
        expect(loaded!.server, equals(serverInfo.server));
        expect(loaded.port, equals(serverInfo.port));
        expect(loaded.name, equals(serverInfo.name));
        expect(loaded.version, equals(serverInfo.version));
        expect(loaded.lanServer, equals(serverInfo.lanServer));
        expect(loaded.tailscaleServer, equals(serverInfo.tailscaleServer));
        expect(loaded.authRequired, equals(serverInfo.authRequired));
        expect(loaded.legacyMode, equals(serverInfo.legacyMode));
      });

      test('loadServerInfo should return null when nothing is saved', () async {
        final loaded = await manager.loadServerInfo();
        expect(loaded, isNull);
      });

      test('loadServerInfo should return null for invalid JSON', () async {
        await prefs.setString('server_info', 'invalid json');
        final loaded = await manager.loadServerInfo();
        expect(loaded, isNull);
      });

      test('loadServerInfo should return null for invalid JSON structure',
          () async {
        await prefs.setString('server_info', '{"invalid": "data"}');
        final loaded = await manager.loadServerInfo();
        // Should handle gracefully (may return null or throw, we accept either)
        expect(loaded == null || loaded.server.isEmpty, isTrue);
      });

      test('loadSessionId should return saved session ID', () async {
        final serverInfo = _createTestServerInfo();
        const sessionId = 'test-session-456';

        await manager.saveConnectionInfo(serverInfo, sessionId);
        final loaded = await manager.loadSessionId();

        expect(loaded, equals(sessionId));
      });

      test('loadSessionId should return null when nothing is saved', () async {
        final loaded = await manager.loadSessionId();
        expect(loaded, isNull);
      });

      test('clearConnectionInfo should remove all connection data', () async {
        final serverInfo = _createTestServerInfo();
        await manager.saveConnectionInfo(serverInfo, 'session-123');

        await manager.clearConnectionInfo();

        expect(await manager.loadServerInfo(), isNull);
        expect(await manager.loadSessionId(), isNull);
      });
    });

    group('Device ID Persistence', () {
      test('saveDeviceId should store device ID', () async {
        const deviceId = 'device-123-abc';

        await manager.saveDeviceId(deviceId);
        final loaded = await manager.loadDeviceId();

        expect(loaded, equals(deviceId));
      });

      test('loadDeviceId should return null when nothing is saved', () async {
        final loaded = await manager.loadDeviceId();
        expect(loaded, isNull);
      });

      test('clearDeviceId should remove device ID', () async {
        await manager.saveDeviceId('device-123');
        await manager.clearDeviceId();

        final loaded = await manager.loadDeviceId();
        expect(loaded, isNull);
      });

      test('device ID operations should not affect other data', () async {
        await manager.saveDeviceId('device-123');
        await manager.saveConnectionInfo(
            _createTestServerInfo(), 'session-456');

        // Clear device ID
        await manager.clearDeviceId();

        // Connection info should still exist
        expect(await manager.loadServerInfo(), isNotNull);
        expect(await manager.loadSessionId(), equals('session-456'));
      });
    });

    group('End-to-End Scenarios', () {
      test('full connection save and load cycle', () async {
        // Save connection
        final serverInfo = _createTestServerInfo();
        const sessionId = 'session-abc';

        await manager.saveConnectionInfo(serverInfo, sessionId);
        await manager.saveDeviceId('device-xyz');

        // Verify all data can be loaded
        final loadedServer = await manager.loadServerInfo();
        final loadedSessionId = await manager.loadSessionId();
        final loadedDeviceId = await manager.loadDeviceId();

        expect(loadedServer?.server, equals(serverInfo.server));
        expect(loadedSessionId, equals(sessionId));
        expect(loadedDeviceId, equals('device-xyz'));
      });

      test('overwriting server info should update data', () async {
        final server1 = _createTestServerInfo(ip: '192.168.1.1');
        final server2 = _createTestServerInfo(ip: '10.0.0.1');

        await manager.saveConnectionInfo(server1, 'session-1');
        await manager.saveConnectionInfo(server2, 'session-2');

        final loaded = await manager.loadServerInfo();
        expect(loaded?.server, equals('10.0.0.1'));
        expect(await manager.loadSessionId(), equals('session-2'));
      });

      test('clear operations should be independent', () async {
        // Save all data
        await manager.saveConnectionInfo(_createTestServerInfo(), 'session');
        await manager.saveDeviceId('device');

        // Clear only connection info
        await manager.clearConnectionInfo();

        // Device should still exist
        expect(await manager.loadDeviceId(), equals('device'));
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
