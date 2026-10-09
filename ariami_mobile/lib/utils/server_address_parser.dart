/// Parses a manually-entered server address into a host + port.
///
/// Accepts the address forms a user is likely to type when the QR code is
/// unavailable, for example:
///
/// ```
/// http://100.x.y.z:8080
/// 100.x.y.z:8080
/// http://192.168.1.50:8080
/// 192.168.1.50:8080
/// ```
///
/// The scheme is optional (assumed `http`), the port is optional (defaults to
/// [defaultPort]). A trailing slash is allowed; other URL paths are rejected.
library;

import 'package:ariami_core/models/server_address.dart';

class ParsedServerAddress {
  static const int defaultPort = 8080;

  final String host;
  final int port;
  final String scheme;
  final String? publicOrigin;

  const ParsedServerAddress({
    required this.host,
    required this.port,
    required this.scheme,
    this.publicOrigin,
  });

  bool get isSecure => publicOrigin != null;

  static ParsedServerAddress? tryParse(String input) {
    final parts = parseServerAddress(input, defaultPort: defaultPort);
    if (parts == null) return null;
    return ParsedServerAddress(
      host: parts.host,
      port: parts.port,
      scheme: parts.scheme,
      publicOrigin: parts.publicOrigin,
    );
  }

  @override
  String toString() =>
      'ParsedServerAddress(host: $host, port: $port, scheme: $scheme)';
}
