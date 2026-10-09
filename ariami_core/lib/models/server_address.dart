/// Parsing for manually-entered server addresses (host, optional scheme/port).
library;

import 'package:ariami_core/models/server_origin.dart';

/// The pieces of a manually-entered server address.
class ServerAddressParts {
  const ServerAddressParts({
    required this.host,
    required this.port,
    required this.scheme,
    this.publicOrigin,
  });

  final String host;
  final int port;
  final String scheme;

  /// Canonical HTTPS origin, set only for `https` addresses.
  final String? publicOrigin;
}

/// Parses [input] into host, port and scheme, or returns `null` when invalid.
///
/// The scheme is optional (assumed `http`, or `https` for a scheme-less host in
/// [bareHttpsHosts]); the port defaults to 443 for `https` and [defaultPort]
/// otherwise. Credentials, queries, fragments and paths other than `/` are
/// rejected, as is an `https` address without a safe public origin.
ServerAddressParts? parseServerAddress(
  String input, {
  int defaultPort = 8080,
  Set<String> bareHttpsHosts = const {},
}) {
  final raw = input.trim();
  if (raw.isEmpty) return null;

  // Prepend a scheme so Uri.parse populates host/port consistently. Without a
  // scheme, "192.168.1.50:8080" is parsed with the host in `scheme`.
  final lower = raw.toLowerCase();
  final hasScheme = lower.startsWith('http://') || lower.startsWith('https://');
  final uri = Uri.tryParse(hasScheme ? raw : 'http://$raw');
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }

  final isBareHttpsHost =
      !hasScheme && bareHttpsHosts.contains(uri.host.toLowerCase());
  final scheme = isBareHttpsHost ? 'https' : uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : defaultPort);
  if (port < 1 || port > 65535) return null;

  final publicOrigin = scheme == 'https'
      ? normalizeSecurePublicOrigin(uri.replace(scheme: 'https').origin)
      : null;
  if (scheme == 'https' && publicOrigin == null) return null;

  return ServerAddressParts(
    host: uri.host,
    port: port,
    scheme: scheme,
    publicOrigin: publicOrigin,
  );
}
