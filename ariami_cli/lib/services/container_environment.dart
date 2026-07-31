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

  /// Port the server should bind. Unlike [advertisedPortOverride], this is the
  /// port the Ariami process actually listens on.
  int? get serverPortOverride => _readPort('ARIAMI_PORT');

  /// The raw `ARIAMI_PORT` value when it was set but not a usable port.
  String? get invalidServerPortValue => _invalidPortValue('ARIAMI_PORT');

  /// Port clients should connect on when the container publishes the server
  /// on a different port than it binds, for example `-p 2000:8080`.
  ///
  /// Null when unset or unusable: advertising a bad port would break every
  /// client, whereas falling back to the bound port only misses the remap the
  /// operator was trying to describe. See [invalidAdvertisedPortValue] to
  /// report the difference.
  int? get advertisedPortOverride => _readPort('ARIAMI_ADVERTISED_PORT');

  /// The raw `ARIAMI_ADVERTISED_PORT` value when it was set but not a usable
  /// port, so callers can warn instead of silently ignoring a typo.
  String? get invalidAdvertisedPortValue =>
      _invalidPortValue('ARIAMI_ADVERTISED_PORT');

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

  int? _readPort(String name) {
    final value = _readTrimmed(name);
    if (value == null) return null;
    final port = int.tryParse(value);
    return port != null && port >= 1 && port <= 65535 ? port : null;
  }

  String? _invalidPortValue(String name) {
    final value = _readTrimmed(name);
    return value != null && _readPort(name) == null ? value : null;
  }

  bool get isContainerized {
    final value = _environment['ARIAMI_CONTAINER']?.trim().toLowerCase();
    return value == '1' || value == 'true' || File(_dockerenvPath).existsSync();
  }
}
