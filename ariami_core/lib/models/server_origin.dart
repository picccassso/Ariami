/// Validation and normalization for Ariami's optional public HTTPS origin.
library;

/// Returns a canonical HTTPS origin suitable for API, media, and WebSocket
/// traffic, or `null` when [value] is not a safe origin.
///
/// Public origins deliberately reject credentials, paths, queries, fragments,
/// and non-HTTPS schemes. Ariami servers expose authentication and media, so a
/// configured public route must never permit a cleartext downgrade.
String? normalizeSecurePublicOrigin(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }

  try {
    return uri.origin;
  } on StateError {
    return null;
  }
}

/// Converts a validated HTTP(S) origin into its WebSocket equivalent.
String websocketOriginFor(String origin) {
  final uri = Uri.parse(origin);
  return uri
      .replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws',
        path: '',
        query: null,
        fragment: null,
      )
      .toString()
      .replaceAll(RegExp(r'/$'), '');
}
