import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum NetworkType {
  wifi,

  mobile,

  none,
}

/// Service for monitoring network connectivity type
///
/// Detects whether the device is on WiFi, mobile data, or offline.
/// Used by QualitySettingsService to determine streaming quality.
class NetworkMonitorService {
  static final NetworkMonitorService _instance =
      NetworkMonitorService._internal();
  factory NetworkMonitorService() => _instance;
  NetworkMonitorService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  NetworkType _currentNetworkType = NetworkType.none;
  final _networkTypeController = StreamController<NetworkType>.broadcast();
  Future<void>? _initFuture;

  Stream<NetworkType> get networkTypeStream => _networkTypeController.stream;

  NetworkType get currentNetworkType => _currentNetworkType;

  /// Initialize the service and start monitoring.
  ///
  /// Idempotent: concurrent or repeat calls share a single initialization so
  /// the connectivity subscription is never created more than once.
  Future<void> initialize() => _initFuture ??= _initialize();

  @visibleForTesting
  void resetForTesting() {
    _subscription?.cancel();
    _subscription = null;
    _initFuture = null;
    _currentNetworkType = NetworkType.none;
  }

  Future<void> _initialize() async {
    final results = await _connectivity.checkConnectivity();
    _updateNetworkType(results);

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateNetworkType(results);
    });

    print('[NetworkMonitorService] Initialized: $_currentNetworkType');
  }

  void _updateNetworkType(List<ConnectivityResult> results) {
    final previousType = _currentNetworkType;

    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      _currentNetworkType = NetworkType.none;
    } else if (results.contains(ConnectivityResult.wifi)) {
      _currentNetworkType = NetworkType.wifi;
    } else if (results.contains(ConnectivityResult.mobile)) {
      _currentNetworkType = NetworkType.mobile;
    } else if (results.contains(ConnectivityResult.ethernet)) {
      // Treat ethernet as WiFi (high bandwidth)
      _currentNetworkType = NetworkType.wifi;
    } else {
      // Other types (bluetooth, vpn, etc.) - treat as mobile (conservative)
      _currentNetworkType = NetworkType.mobile;
    }

    if (previousType != _currentNetworkType) {
      print('[NetworkMonitorService] Network changed: $previousType -> $_currentNetworkType');
      _networkTypeController.add(_currentNetworkType);
    }
  }

  bool get isOnWifi => _currentNetworkType == NetworkType.wifi;

  bool get isOnMobileData => _currentNetworkType == NetworkType.mobile;

  bool get isOffline => _currentNetworkType == NetworkType.none;

  void dispose() {
    _subscription?.cancel();
    _networkTypeController.close();
  }
}
