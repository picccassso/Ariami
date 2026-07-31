import 'package:ariami_cli/services/container_networking_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('warns for a likely Docker bridge address', () {
    final hint = buildContainerNetworkingHint(
      isContainerized: true,
      detectedLanHost: '172.17.0.2',
      hasAdvertisedHostOverride: false,
    );

    expect(hint, contains('Docker bridge networking detected'));
    expect(hint, contains('network_mode: host'));
    expect(hint, contains('ARIAMI_ADVERTISED_LAN_HOST'));
  });

  test('does not repeat host-override guidance when one is set', () {
    final hint = buildContainerNetworkingHint(
      isContainerized: true,
      detectedLanHost: '172.31.255.2',
      hasAdvertisedHostOverride: true,
    );

    expect(hint, isNotNull);
    expect(hint, isNot(contains('ARIAMI_ADVERTISED_LAN_HOST')));
  });

  test('does not warn outside a likely bridged container', () {
    expect(
      buildContainerNetworkingHint(
        isContainerized: true,
        detectedLanHost: '192.168.1.50',
        hasAdvertisedHostOverride: false,
      ),
      isNull,
    );
    expect(
      buildContainerNetworkingHint(
        isContainerized: false,
        detectedLanHost: '172.17.0.2',
        hasAdvertisedHostOverride: false,
      ),
      isNull,
    );
  });
}
