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

import 'package:ariami_core/models/server_origin.dart';

class ParsedServerAddress {
  /// Default server port used when the address omits one.
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

  /// Parse [input] into a [ParsedServerAddress], or return `null` if it is not
  /// a usable `host[:port]` address.
  static ParsedServerAddress? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Prepend a scheme so Uri.parse populates host/port consistently. Without a
    // scheme, "192.168.1.50:8080" is parsed with the host in `scheme`.
    final lower = trimmed.toLowerCase();
    final hasScheme =
        lower.startsWith('http://') || lower.startsWith('https://');
    final normalized = hasScheme ? trimmed : 'http://$trimmed';

    final Uri uri;
    try {
      uri = Uri.parse(normalized);
    } catch (_) {
      return null;
    }

    final host = uri.host;
    if (host.isEmpty) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
    if (uri.path.isNotEmpty && uri.path != '/') return null;

    final port =
        uri.hasPort ? uri.port : (scheme == 'https' ? 443 : defaultPort);
    if (port < 1 || port > 65535) return null;

    final publicOrigin =
        scheme == 'https' ? normalizeSecurePublicOrigin(uri.origin) : null;
    if (scheme == 'https' && publicOrigin == null) return null;

    return ParsedServerAddress(
      host: host,
      port: port,
      scheme: scheme,
      publicOrigin: publicOrigin,
    );
  }

  @override
  String toString() =>
      'ParsedServerAddress(host: $host, port: $port, scheme: $scheme)';
}
