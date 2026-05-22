import 'dart:async';

/// Discovered network endpoints for server advertisement.
class NetworkEndpoints {
  final String? tailscaleIp;
  final String? lanIp;

  const NetworkEndpoints({
    this.tailscaleIp,
    this.lanIp,
  });

  bool matches(NetworkEndpoints other) {
    return tailscaleIp == other.tailscaleIp && lanIp == other.lanIp;
  }
}

/// Periodically re-probes network endpoints via a host-provided callback.
class NetworkEndpointMonitor {
  NetworkEndpointMonitor({
    required void Function(NetworkEndpoints endpoints) onChanged,
    Duration pollInterval = const Duration(seconds: 30),
  })  : _onChanged = onChanged,
        _pollInterval = pollInterval;

  final void Function(NetworkEndpoints endpoints) _onChanged;
  final Duration _pollInterval;

  Timer? _timer;
  Future<NetworkEndpoints> Function()? _discoveryCallback;
  NetworkEndpoints? _lastKnown;
  bool _isProbing = false;

  void setDiscoveryCallback(Future<NetworkEndpoints> Function() callback) {
    _discoveryCallback = callback;
  }

  void start() {
    stop();
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_probe()));
    unawaited(_probe());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _probe() async {
    final callback = _discoveryCallback;
    if (callback == null || _isProbing) {
      return;
    }

    _isProbing = true;
    try {
      final endpoints = await callback();
      if (_lastKnown != null && _lastKnown!.matches(endpoints)) {
        return;
      }

      _lastKnown = endpoints;
      _onChanged(endpoints);
    } catch (e) {
      print('[NetworkEndpointMonitor] Probe failed: $e');
    } finally {
      _isProbing = false;
    }
  }
}
