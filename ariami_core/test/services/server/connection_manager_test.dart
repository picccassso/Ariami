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

    test('listeners may remove themselves during notification', () {
      final cm = ConnectionManager();
      var calls = 0;
      late void Function() listener;
      listener = () {
        calls++;
        cm.removeListener(listener);
      };
      cm.addListener(listener);

      cm.registerClient('d1', 'Some Device');
      cm.registerClient('d2', 'Another Device');

      expect(calls, 1);
    });
  });
}
