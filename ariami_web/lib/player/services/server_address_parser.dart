class ParsedServerAddress {
  const ParsedServerAddress({required this.host, required this.port});

  static const int defaultPort = 8080;

  final String host;
  final int port;

  /// Accepts `host`, `host:port`, or an HTTP URL. Paths are ignored.
  static ParsedServerAddress? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final hasScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');
    final uri = Uri.tryParse(hasScheme ? trimmed : 'http://$trimmed');
    if (uri == null || uri.host.isEmpty) return null;

    try {
      final port = uri.hasPort ? uri.port : defaultPort;
      if (port < 1 || port > 65535) return null;
      return ParsedServerAddress(host: uri.host, port: port);
    } on FormatException {
      return null;
    }
  }
}
