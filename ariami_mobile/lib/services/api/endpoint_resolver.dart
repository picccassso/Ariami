import 'dart:async';
import 'dart:io';

import '../quality/network_monitor_service.dart';

/// Resolves the best available endpoint, preferring LAN when reachable.
class EndpointResolver {
  static final EndpointResolver _instance = EndpointResolver._internal();
  factory EndpointResolver() => _instance;
  EndpointResolver._internal();

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  Timer? _timer;
  StreamSubscription<NetworkType>? _networkSubscription;
  String? _lanIp;
  String? _primaryIp;
  int? _port;
  String? _activeIp;
  bool _isProbing = false;

  Stream<String> get endpointChangedStream => _controller.stream;

  void configure({
    required String primaryIp,
    String? lanIp,
    required int port,
    String? activeIp,
  }) {
    _primaryIp = primaryIp;
    _lanIp = lanIp;
    _port = port;
    _activeIp = activeIp ?? primaryIp;
  }

  Future<String> resolve() async {
    final primaryIp = _primaryIp;
    final port = _port;
    if (primaryIp == null || port == null) {
      throw StateError('EndpointResolver used before configure()');
    }

    final lanIp = _lanIp;
    if (lanIp == null || lanIp.isEmpty || lanIp == primaryIp) {
      return primaryIp;
    }

    if (await _isReachable(lanIp, port)) {
      return lanIp;
    }

    return primaryIp;
  }

  void startMonitoring() {
    stopMonitoring();

    if (_primaryIp == null || _port == null) {
      return;
    }

    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_probeNow()),
    );
    _networkSubscription = NetworkMonitorService().networkTypeStream.listen(
          (_) => unawaited(_probeNow()),
        );
    unawaited(_probeNow());
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
    _networkSubscription?.cancel();
    _networkSubscription = null;
    _isProbing = false;
  }

  Future<void> _probeNow() async {
    if (_isProbing || _primaryIp == null || _port == null) {
      return;
    }

    _isProbing = true;
    try {
      final resolvedIp = await resolve();
      if (resolvedIp == _activeIp) {
        return;
      }

      _activeIp = resolvedIp;
      _controller.add(resolvedIp);
    } finally {
      _isProbing = false;
    }
  }

  Future<bool> _isReachable(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
