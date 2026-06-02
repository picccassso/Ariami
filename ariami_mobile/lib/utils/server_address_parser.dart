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
/// [defaultPort]), and any trailing path/slash is ignored.
library;

class ParsedServerAddress {
  /// Default server port used when the address omits one.
  static const int defaultPort = 8080;

  final String host;
  final int port;

  const ParsedServerAddress({required this.host, required this.port});

  /// Parse [input] into a [ParsedServerAddress], or return `null` if it is not
  /// a usable `host[:port]` address.
  static ParsedServerAddress? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Prepend a scheme so Uri.parse populates host/port consistently. Without a
    // scheme, "192.168.1.50:8080" is parsed with the host in `scheme`.
    final hasScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');
    final normalized = hasScheme ? trimmed : 'http://$trimmed';

    final Uri uri;
    try {
      uri = Uri.parse(normalized);
    } catch (_) {
      return null;
    }

    final host = uri.host;
    if (host.isEmpty) return null;

    final port = uri.hasPort ? uri.port : defaultPort;
    if (port < 1 || port > 65535) return null;

    return ParsedServerAddress(host: host, port: port);
  }

  @override
  String toString() => 'ParsedServerAddress(host: $host, port: $port)';
}
