import 'package:ariami_core/services/server/connection_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectionManager', () {
    test('registerOrRefreshClient can upgrade clientType to dashboard', () {
      final cm = ConnectionManager();
      cm.registerClient('d1', 'Some Device', userId: 'u1', clientType: null);
      expect(cm.mobileClientCount, 1);
      expect(cm.clientCount, 1);

      cm.registerOrRefreshClient(
        'd1',
        'Some Device',
        userId: 'u1',
        clientType: 'dashboard',
      );

      expect(cm.mobileClientCount, 0);
      expect(cm.getClient('d1')?.clientType, 'dashboard');
    });
  });
}
