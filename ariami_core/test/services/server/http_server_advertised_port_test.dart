import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('AriamiHttpServer.setAdvertisedPort', () {
    late AriamiHttpServer server;
    late Directory testDir;

    setUp(() async {
      // AriamiHttpServer is a singleton and stop() does not clear it, so the
      // override has to be reset explicitly between tests.
      server = AriamiHttpServer();
      await server.stop();
      server.setAdvertisedPort(null);
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_adv_port_');
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );
    });

    tearDown(() async {
      await server.stop();
      server.setAdvertisedPort(null);
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    // Port 0 lets the OS pick, so the bound port is never 2000 and the two
    // ports below are always distinguishable. `attemptedPort` reports the
    // bound port here: only startWithPortFallback sets it separately.
    Future<void> startOnEphemeralPort() async {
      await server.start(
        advertisedIp: '127.0.0.1',
        lanIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: 0,
      );
    }

    test('advertises the bound port when no override is set', () async {
      await startOnEphemeralPort();
      final info = server.getServerInfo();

      expect(info['port'], greaterThan(0));
      expect(info['port'], info['attemptedPort']);
    });

    test('advertises the override instead of the bound port', () async {
      // Set before start(), the order the discovery responder depends on.
      server.setAdvertisedPort(2000);
      await startOnEphemeralPort();

      final info = server.getServerInfo();
      expect(info['port'], 2000);
      // Binding is untouched: diagnostics still describe what is listening.
      expect(info['attemptedPort'], isNot(2000));
      expect(info['attemptedPort'], greaterThan(0));
    });

    test('clearing the override returns to the bound port', () async {
      server.setAdvertisedPort(2000);
      await startOnEphemeralPort();
      expect(server.getServerInfo()['port'], 2000);

      server.setAdvertisedPort(null);
      final info = server.getServerInfo();
      expect(info['port'], info['attemptedPort']);
    });

    test('rejects ports outside the valid range', () {
      expect(() => server.setAdvertisedPort(0), throwsArgumentError);
      expect(() => server.setAdvertisedPort(-1), throwsArgumentError);
      expect(() => server.setAdvertisedPort(65536), throwsArgumentError);

      server.setAdvertisedPort(1);
      server.setAdvertisedPort(65535);
    });
  });
}
