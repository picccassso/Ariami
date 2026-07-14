import 'dart:io';

/// Detects whether Ariami is running in a container and which host should be
/// advertised to other devices.
class ContainerEnvironment {
  ContainerEnvironment({
    Map<String, String>? environment,
    String dockerenvPath = '/.dockerenv',
  })  : _environment = environment ?? Platform.environment,
        _dockerenvPath = dockerenvPath;

  final Map<String, String> _environment;
  final String _dockerenvPath;

  String? get advertisedHostOverride {
    return _readTrimmed('ARIAMI_ADVERTISED_HOST');
  }

  String? get advertisedLanHostOverride {
    return _readTrimmed('ARIAMI_ADVERTISED_LAN_HOST');
  }

  String? get advertisedTailscaleHostOverride {
    return _readTrimmed('ARIAMI_ADVERTISED_TAILSCALE_HOST');
  }

  /// HTTPS origin exposed by a trusted reverse proxy, for example
  /// `https://review.ariami.xyz`.
  String? get publicOriginOverride {
    return _readTrimmed('ARIAMI_PUBLIC_ORIGIN');
  }

  bool get hasAnyAdvertisedOverride {
    return advertisedHostOverride != null ||
        advertisedLanHostOverride != null ||
        advertisedTailscaleHostOverride != null;
  }

  String? _readTrimmed(String name) {
    final value = _environment[name]?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  bool get isContainerized {
    final value = _environment['ARIAMI_CONTAINER']?.trim().toLowerCase();
    return value == '1' || value == 'true' || File(_dockerenvPath).existsSync();
  }
}
