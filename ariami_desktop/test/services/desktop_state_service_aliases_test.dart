import 'package:ariami_desktop/services/desktop_state_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopStateService endpoint aliases', () {
    late DesktopStateService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = DesktopStateService();
    });

    test('are null until set', () async {
      expect(await service.getLanServerAlias(), isNull);
      expect(await service.getTailscaleServerAlias(), isNull);
    });

    test('persist trimmed values for both endpoints', () async {
      await service.setEndpointAliases(
        lanAlias: '  Living room  ',
        tailscaleAlias: 'Away',
      );

      expect(await service.getLanServerAlias(), 'Living room');
      expect(await service.getTailscaleServerAlias(), 'Away');
    });

    test('a null or blank alias clears only that endpoint', () async {
      await service.setEndpointAliases(
          lanAlias: 'Home', tailscaleAlias: 'Away');
      await service.setEndpointAliases(lanAlias: '   ', tailscaleAlias: 'Away');

      expect(await service.getLanServerAlias(), isNull);
      expect(await service.getTailscaleServerAlias(), 'Away');
    });

    test('are removed by a setup reset', () async {
      await service.setEndpointAliases(
          lanAlias: 'Home', tailscaleAlias: 'Away');

      await service.clearSetupPreferences();

      expect(await service.getLanServerAlias(), isNull);
      expect(await service.getTailscaleServerAlias(), isNull);
    });
  });
}
