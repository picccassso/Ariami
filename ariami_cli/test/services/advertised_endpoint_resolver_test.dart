import 'package:ariami_cli/services/advertised_endpoint_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers detected Tailscale over detected LAN', () {
    final result = resolveAdvertisedEndpoints(
      bindHost: '0.0.0.0',
      detectedTailscaleHost: '100.64.10.20',
      detectedLanHost: '192.168.1.50',
    );

    expect(result.advertisedIp, '100.64.10.20');
    expect(result.tailscaleIp, '100.64.10.20');
    expect(result.lanIp, '192.168.1.50');
  });

  test('keeps the generic override primary when Tailscale appears', () {
    final result = resolveAdvertisedEndpoints(
      bindHost: '0.0.0.0',
      detectedTailscaleHost: '100.64.10.20',
      detectedLanHost: '192.168.1.50',
      advertisedHostOverride: 'docker-media-vm.infra.example.com',
    );

    expect(result.advertisedIp, 'docker-media-vm.infra.example.com');
    expect(result.tailscaleIp, '100.64.10.20');
    expect(result.lanIp, 'docker-media-vm.infra.example.com');
  });

  test('a LAN override does not stop detected Tailscale updates', () {
    final result = resolveAdvertisedEndpoints(
      bindHost: '0.0.0.0',
      detectedTailscaleHost: '100.64.10.20',
      detectedLanHost: '172.17.0.2',
      advertisedLanHostOverride: 'docker-media-vm.infra.example.com',
    );

    expect(result.advertisedIp, '100.64.10.20');
    expect(result.tailscaleIp, '100.64.10.20');
    expect(result.lanIp, 'docker-media-vm.infra.example.com');
  });

  test('loopback binding remains advertised as localhost after refresh', () {
    final result = resolveAdvertisedEndpoints(
      bindHost: '127.0.0.1',
      detectedTailscaleHost: '100.64.10.20',
      detectedLanHost: '192.168.1.50',
    );

    expect(result.advertisedIp, 'localhost');
    expect(result.tailscaleIp, '100.64.10.20');
    expect(result.lanIp, '192.168.1.50');
  });
}
