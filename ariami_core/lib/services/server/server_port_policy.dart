import 'dart:io';

/// Thrown when Ariami cannot bind any candidate port.
class PortBindingException implements Exception {
  PortBindingException({
    required this.preferredPort,
    required this.candidates,
    this.explicitPort = false,
  }) : message = explicitPort
            ? 'Port $preferredPort is already in use. Choose another port with '
                '--port or free the port.'
            : 'Could not bind ports ${ServerPortPolicy.fallbackRangeStart}-'
                '${ServerPortPolicy.fallbackRangeEnd}. Free a port or run: '
                'ariami_cli start --port 9000';

  final int preferredPort;
  final List<int> candidates;
  final bool explicitPort;
  final String message;

  @override
  String toString() => message;
}

/// Builds ordered port candidates and formats fallback messaging.
class ServerPortPolicy {
  static const int defaultPort = 8080;
  static const int fallbackRangeStart = 8080;
  static const int fallbackRangeEnd = 8099;

  /// Ordered unique candidates: [savedPort?, preferredPort, 8080..8099].
  static List<int> buildCandidates({
    required int preferredPort,
    int? savedPort,
    bool allowFallback = true,
  }) {
    if (!allowFallback) {
      return [preferredPort];
    }

    final seen = <int>{};
    final candidates = <int>[];

    void add(int port) {
      if (seen.add(port)) {
        candidates.add(port);
      }
    }

    if (savedPort != null) {
      add(savedPort);
    }
    add(preferredPort);
    for (var port = fallbackRangeStart; port <= fallbackRangeEnd; port++) {
      add(port);
    }

    return candidates;
  }

  static bool isAddressInUseError(Object error) {
    final text = error.toString();
    if (text.contains('Address already in use')) {
      return true;
    }
    if (error is SocketException) {
      return text.contains('SocketException');
    }
    return false;
  }

  static String? formatFallbackMessage({
    required int attemptedPort,
    required int actualPort,
  }) {
    if (attemptedPort == actualPort) {
      return null;
    }
    return 'Port $attemptedPort was in use, so Ariami started on $actualPort.';
  }
}
