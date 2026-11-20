class ParsedServerAddress {
  const ParsedServerAddress({
    required this.host,
    required this.port,
    this.scheme = 'http',
  });

  static const int defaultPort = 8080;

  final String host;
  final int port;
  final String scheme;

  /// Accepts `host`, `host:port`, or an HTTP(S) URL. Paths are ignored.
  static ParsedServerAddress? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final lower = trimmed.toLowerCase();
    final hasScheme =
        lower.startsWith('http://') || lower.startsWith('https://');
    final uri = Uri.tryParse(hasScheme ? trimmed : 'http://$trimmed');
    if (uri == null || uri.host.isEmpty) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;

    try {
      final port = uri.hasPort
          ? uri.port
          : (scheme == 'https' ? 443 : defaultPort);
      if (port < 1 || port > 65535) return null;
      return ParsedServerAddress(host: uri.host, port: port, scheme: scheme);
    } on FormatException {
      return null;
    }
  }
}
