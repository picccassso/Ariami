import 'package:ariami_cli/services/cli_state_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CliStateService transcode slots', () {
    test('setTranscodeSlotsOverride stores and clears value', () async {
      final service = CliStateService();
      await service.clearConfig();

      expect(await service.getTranscodeSlotsOverride(), isNull);

      await service.setTranscodeSlotsOverride(5);
      expect(await service.getTranscodeSlotsOverride(), 5);

      await service.setTranscodeSlotsOverride(null);
      expect(await service.getTranscodeSlotsOverride(), isNull);
    });
  });
}
