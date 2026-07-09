/// Strict validation for scanned Ariami pairing-QR payloads.
///
/// The QR scanner previously fed any decodable JSON straight into
/// `ServerInfo.fromJson`, so arbitrary QR codes (WiFi share codes, URLs,
/// hostile payloads) produced confusing failures or half-valid ServerInfo
/// objects. This parser accepts only payloads that structurally match what the
/// desktop/CLI server encodes, with type and range checks on every field.
///
/// Error messages are intentionally generic: they must never echo the scanned
/// payload back (it may contain a registration token or be attacker-chosen).
library;

import 'dart:convert';

import '../models/server_info.dart';

class QrPayloadResult {
  final ServerInfo? serverInfo;

  /// User-facing reason when parsing failed. Never contains payload content.
  final String? error;

  const QrPayloadResult._({this.serverInfo, this.error});

  bool get isValid => serverInfo != null;

  factory QrPayloadResult.ok(ServerInfo serverInfo) =>
      QrPayloadResult._(serverInfo: serverInfo);

  factory QrPayloadResult.fail(String error) => QrPayloadResult._(error: error);
}

class QrPayloadParser {
  /// Generous upper bound; real payloads are a few hundred bytes and QR codes
  /// top out around 3 KB. Anything larger is not ours.
  static const int maxPayloadLength = 4096;

  static const int _maxHostLength = 253;
  static const int _maxNameLength = 120;
  static const int _maxVersionLength = 40;
  static const int _maxTokenLength = 128;

  static const String _notAriamiMessage =
      'This isn\'t an Ariami pairing code. Scan the QR shown by your '
      'desktop server.';

  /// Hostname / IPv4 shape: alphanumeric labels with dots and dashes.
  static final RegExp _hostPattern =
      RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.\-]*[A-Za-z0-9])?$');

  /// Registration tokens are hex (QR) or the unambiguous invite alphabet.
  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9]+$');

  static QrPayloadResult parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > maxPayloadLength) {
      return QrPayloadResult.fail(_notAriamiMessage);
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return QrPayloadResult.fail(_notAriamiMessage);
    }
    if (decoded is! Map) {
      return QrPayloadResult.fail(_notAriamiMessage);
    }
    final json = Map<String, dynamic>.from(decoded);

    final server = _validHost(json['server']);
    if (server == null) {
      return QrPayloadResult.fail(_notAriamiMessage);
    }

    final port = json['port'];
    if (port is! int || port < 1 || port > 65535) {
      return QrPayloadResult.fail(_notAriamiMessage);
    }

    // Optional endpoints must be valid hosts when present at all.
    String? lanServer;
    if (json.containsKey('lanServer') && json['lanServer'] != null) {
      lanServer = _validHost(json['lanServer']);
      if (lanServer == null) {
        return QrPayloadResult.fail(_notAriamiMessage);
      }
    }
    String? tailscaleServer;
    if (json.containsKey('tailscaleServer') &&
        json['tailscaleServer'] != null) {
      tailscaleServer = _validHost(json['tailscaleServer']);
      if (tailscaleServer == null) {
        return QrPayloadResult.fail(_notAriamiMessage);
      }
    }

    // Auth flags drive the login/register routing decision; a payload with
    // mistyped flags must be rejected rather than silently defaulted, so a
    // crafted QR can't route around the login screen.
    final authRequired = json['authRequired'];
    if (authRequired != null && authRequired is! bool) {
      return QrPayloadResult.fail(_notAriamiMessage);
    }
    final legacyMode = json['legacyMode'];
    if (legacyMode != null && legacyMode is! bool) {
      return QrPayloadResult.fail(_notAriamiMessage);
    }

    String? registrationToken;
    final rawToken = json['registrationToken'];
    if (rawToken != null) {
      if (rawToken is! String ||
          rawToken.isEmpty ||
          rawToken.length > _maxTokenLength ||
          !_tokenPattern.hasMatch(rawToken)) {
        return QrPayloadResult.fail(_notAriamiMessage);
      }
      registrationToken = rawToken;
    }

    final name = _cappedString(json['name'], _maxNameLength);
    final version = _cappedString(json['version'], _maxVersionLength);
    if (name == null || version == null) {
      return QrPayloadResult.fail(_notAriamiMessage);
    }

    final rawLimits = json['downloadLimits'];
    if (rawLimits != null && rawLimits is! Map) {
      return QrPayloadResult.fail(_notAriamiMessage);
    }

    // Reuse the model's own construction (tailscale derivation, limits
    // defaults) now that every field is known to be well-typed.
    try {
      final serverInfo = ServerInfo.fromJson(<String, dynamic>{
        'server': server,
        'lanServer': lanServer,
        'tailscaleServer': tailscaleServer,
        'port': port,
        'name': name.isEmpty ? server : name,
        'version': version,
        'authRequired': authRequired ?? false,
        'legacyMode': legacyMode ?? true,
        'registrationToken': registrationToken,
        'downloadLimits': rawLimits == null
            ? null
            : Map<String, dynamic>.from(rawLimits as Map),
      });
      return QrPayloadResult.ok(serverInfo);
    } catch (_) {
      return QrPayloadResult.fail(_notAriamiMessage);
    }
  }

  /// Validate a host value: hostname/IPv4 shape, or a bracket-free IPv6
  /// literal. Rejects schemes, paths, credentials, and whitespace.
  static String? _validHost(dynamic value) {
    if (value is! String) return null;
    final host = value.trim();
    if (host.isEmpty || host.length > _maxHostLength) return null;

    if (host.contains(':')) {
      // IPv6 literal (e.g. Tailscale fd7a:...). Must round-trip through Uri.
      final uri = Uri.tryParse('http://[$host]:1/');
      if (uri == null || uri.host.isEmpty) return null;
      return host;
    }

    if (!_hostPattern.hasMatch(host)) return null;
    return host;
  }

  static String? _cappedString(dynamic value, int maxLength) {
    if (value == null) return '';
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.length <= maxLength
        ? trimmed
        : trimmed.substring(0, maxLength);
  }
}
