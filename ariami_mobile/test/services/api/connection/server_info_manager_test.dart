import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/services/api/connection/server_info_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerInfoManager.applyEndpointRefresh', () {
    test('detects null to Tailscale endpoint configuration change', () {
      final manager = ServerInfoManager();
      final current = ServerInfo(
        server: '192.168.1.50',
        lanServer: '192.168.1.50',
        tailscaleServer: null,
        port: 8080,
        name: 'Ariami',
        version: '4.4.0',
      );
      final fetched = ServerInfo(
        server: '100.64.10.20',
        lanServer: '192.168.1.50',
        tailscaleServer: '100.64.10.20',
        port: 8080,
        name: 'Ariami',
        version: '4.4.0',
      );

      manager.setServerInfo(current);
      final result = manager.applyEndpointRefresh(current, fetched);

      expect(result.endpointConfigChanged, isTrue);
      expect(result.serverInfo.tailscaleServer, '100.64.10.20');
      expect(result.serverInfo.lanServer, '192.168.1.50');
      expect(result.serverInfo.server, '192.168.1.50');
      expect(manager.serverInfo?.tailscaleServer, '100.64.10.20');
    });

    test('does not mark config changed when endpoints are unchanged', () {
      final manager = ServerInfoManager();
      final current = ServerInfo(
        server: '100.64.10.20',
        lanServer: '192.168.1.50',
        tailscaleServer: '100.64.10.20',
        port: 8080,
        name: 'Ariami',
        version: '4.4.0',
      );
      final fetched = ServerInfo(
        server: '100.64.10.20',
        lanServer: '192.168.1.50',
        tailscaleServer: '100.64.10.20',
        port: 8080,
        name: 'Ariami Updated',
        version: '4.3.1',
      );

      final result = manager.applyEndpointRefresh(current, fetched);

      expect(result.endpointConfigChanged, isFalse);
      expect(result.serverInfo.name, 'Ariami Updated');
      expect(result.serverInfo.version, '4.3.1');
    });
  });
}
