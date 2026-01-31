import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Types of network connection
enum NetworkType {
  /// Connected via WiFi
  wifi,

  /// Connected via mobile data (cellular)
  mobile,

  /// No network connection
  none,
}

/// Service for monitoring network connectivity type
///
/// Detects whether the device is on WiFi, mobile data, or offline.
/// Used by QualitySettingsService to determine streaming quality.
class NetworkMonitorService {
  // Singleton pattern
  static final NetworkMonitorService _instance =
      NetworkMonitorService._internal();
  factory NetworkMonitorService() => _instance;
  NetworkMonitorService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  NetworkType _currentNetworkType = NetworkType.none;
  final _networkTypeController = StreamController<NetworkType>.broadcast();

  /// Stream of network type changes
  Stream<NetworkType> get networkTypeStream => _networkTypeController.stream;

  /// Current network type
  NetworkType get currentNetworkType => _currentNetworkType;

  /// Initialize the service and start monitoring
  Future<void> initialize() async {
    // Get initial connectivity state
    final results = await _connectivity.checkConnectivity();
    _updateNetworkType(results);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateNetworkType(results);
    });

    print('[NetworkMonitorService] Initialized: $_currentNetworkType');
  }

  /// Update network type from connectivity results
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

  /// Check if currently on WiFi
  bool get isOnWifi => _currentNetworkType == NetworkType.wifi;

  /// Check if currently on mobile data
  bool get isOnMobileData => _currentNetworkType == NetworkType.mobile;

  /// Check if currently offline
  bool get isOffline => _currentNetworkType == NetworkType.none;

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
    _networkTypeController.close();
  }
}
