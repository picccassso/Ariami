import 'package:ariami_cli/services/cli_state_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CliStateService endpoint aliases', () {
    test('setEndpointAliases stores and clears LAN and Tailscale aliases', () async {
      final service = CliStateService();
      await service.clearConfig();

      expect(await service.getLanServerAlias(), isNull);
      expect(await service.getTailscaleServerAlias(), isNull);

      await service.setEndpointAliases(
        lanAlias: 'Living Room Studio',
        tailscaleAlias: 'Alex Tailscale Node',
      );

      expect(await service.getLanServerAlias(), 'Living Room Studio');
      expect(await service.getTailscaleServerAlias(), 'Alex Tailscale Node');

      // Clear LAN alias only
      await service.setEndpointAliases(
        lanAlias: '',
        tailscaleAlias: 'Alex Tailscale Node',
      );
      expect(await service.getLanServerAlias(), isNull);
      expect(await service.getTailscaleServerAlias(), 'Alex Tailscale Node');

      // Clear Tailscale alias too
      await service.setEndpointAliases(
        lanAlias: null,
        tailscaleAlias: null,
      );
      expect(await service.getLanServerAlias(), isNull);
      expect(await service.getTailscaleServerAlias(), isNull);
    });
  });
}
