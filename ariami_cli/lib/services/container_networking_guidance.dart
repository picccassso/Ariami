String? buildContainerNetworkingHint({
  required bool isContainerized,
  required String? detectedLanHost,
  required bool hasAdvertisedHostOverride,
}) {
  if (!isContainerized || !_isLikelyDockerBridgeIpv4(detectedLanHost)) {
    return null;
  }

  final hostGuidance = hasAdvertisedHostOverride
      ? ''
      : ' Set ARIAMI_ADVERTISED_LAN_HOST (and ARIAMI_ADVERTISED_PORT when '
          'remapped) so generated connection details use the host address.';
  return 'Docker bridge networking detected ($detectedLanHost). Automatic '
      'LAN discovery may not reach this container. On Linux, use '
      'network_mode: host for automatic TV discovery; otherwise enter the '
      'server manually on TV clients.$hostGuidance';
}

bool _isLikelyDockerBridgeIpv4(String? value) {
  if (value == null) return false;
  final octets = value.split('.').map(int.tryParse).toList();
  if (octets.length != 4 || octets.any((octet) => octet == null)) return false;
  return octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31;
}
