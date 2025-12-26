import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:audio_service/audio_service.dart';
import 'utils/constants.dart';
import 'screens/welcome_screen.dart';
import 'screens/setup/tailscale_check_screen.dart';
import 'screens/setup/qr_scanner_screen.dart';
import 'screens/setup/permissions_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/reconnect_screen.dart';
import 'services/api/connection_service.dart';
import 'services/audio/audio_handler.dart';
import 'services/offline/offline_playback_service.dart';
import 'services/download/download_manager.dart';
import 'services/cache/cache_manager.dart';
import 'services/stats/streaming_stats_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// Global audio handler instance - accessible throughout the app
// Nullable because initialization might fail on some devices
AriamiAudioHandler? audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('[Main] ========================================');
  print('[Main] Starting AudioService initialization...');
  print('[Main] ========================================');

  // Initialize the audio service with our custom handler
  // This creates the foreground service for background playback
  try {
    print('[Main] Step 1: Creating AudioServiceConfig...');
    final config = AudioServiceConfig(
      androidNotificationChannelId: 'com.example.ariami_mobile.audio',
      androidNotificationChannelName: 'Ariami Music Playback',
      androidNotificationChannelDescription: 'Controls for music playback',
      androidNotificationOngoing: false, // Changed: Must be false when androidStopForegroundOnPause is false
      androidShowNotificationBadge: true,
      androidStopForegroundOnPause: false, // Keep service alive even when paused
      androidNotificationIcon: 'mipmap/ic_launcher',
    );
    print('[Main] Step 2: Config created successfully');

    print('[Main] Step 3: Calling AudioService.init()...');
    audioHandler = await AudioService.init(
      builder: () {
        print('[Main] Step 4: Builder called - creating AriamiAudioHandler...');
        return AriamiAudioHandler();
      },
      config: config,
    );
    print('[Main] ✅ AudioService initialized successfully!');
    print('[Main] audioHandler is: ${audioHandler != null ? "NOT NULL" : "NULL"}');
    print('[Main] audioHandler type: ${audioHandler.runtimeType}');
    print('[Main] audioHandler hashCode: ${audioHandler.hashCode}');
  } catch (e, stackTrace) {
    print('[Main] ❌ ERROR initializing AudioService!');
    print('[Main] Error type: ${e.runtimeType}');
    print('[Main] Error message: $e');
    print('[Main] Stack trace:');
    print(stackTrace);
    // audioHandler remains null - app can still function without background audio
    // but audio playback will gracefully fail
  }

  print('[Main] ========================================');
  print('[Main] AudioService initialization complete');
  print('[Main] ========================================');

  // Enable high refresh rate on supported devices
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (e) {
    // Ignore errors on unsupported devices
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ConnectionService _connectionService = ConnectionService();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final DownloadManager _downloadManager = DownloadManager();
  final CacheManager _cacheManager = CacheManager();
  final StreamingStatsService _statsService = StreamingStatsService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _isLoading = true;
  Widget? _initialScreen;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _networkDebounceTimer;

  @override
  void initState() {
    super.initState();
    _initializeAndDetermineScreen();
    _listenToConnectionChanges();
    _listenToNetworkChanges();
  }

  /// Initialize services and determine initial screen (must be sequential)
  Future<void> _initializeAndDetermineScreen() async {
    await _initializeServices();
    await _determineInitialScreen();
  }

  /// Initialize background services
  Future<void> _initializeServices() async {
    // Initialize offline playback service (listens to connection changes)
    await _offlineService.initialize();
    // Initialize download manager
    await _downloadManager.initialize();
    // Initialize cache manager for artwork and song caching
    await _cacheManager.initialize();
    // Initialize streaming stats service for play tracking
    await _statsService.initialize();
    print('[Main] Offline, Download, Cache, and Stats services initialized');
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _networkDebounceTimer?.cancel();
    super.dispose();
  }

  /// Listen for connection state changes
  void _listenToConnectionChanges() {
    _connectionSubscription = _connectionService.connectionStateStream.listen(
      (isConnected) {
        if (!isConnected && _connectionService.hasServerInfo) {
          // Connection lost - check offline mode state
          if (_offlineService.isManualOfflineModeEnabled) {
            // Manual offline mode - user chose to go offline, stay in app
            print('Connection lost but manual offline mode enabled - staying in app');
          } else if (_offlineService.offlineMode == OfflineMode.autoOffline) {
            // Auto offline mode - connection lost, stay in app and auto-reconnect
            print('Auto offline mode - staying in app, will auto-reconnect');
          } else {
            // Not in any offline mode - navigate to reconnect screen
            print('Connection lost - navigating to reconnect screen');
            _navigatorKey.currentState?.pushNamedAndRemoveUntil(
              '/reconnect',
              (route) => false,
            );
          }
        }
      },
    );
  }

  /// Listen for network connectivity changes
  void _listenToNetworkChanges() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        // Debounce rapid network transitions (WiFi ↔ cellular)
        _networkDebounceTimer?.cancel();
        _networkDebounceTimer = Timer(const Duration(milliseconds: 500), () {
          _handleNetworkChange(results);
        });
      },
    );
  }

  /// Handle network connectivity change
  void _handleNetworkChange(List<ConnectivityResult> results) {
    // Check if we have any network connectivity
    final hasNetwork = results.any((result) =>
      result == ConnectivityResult.wifi ||
      result == ConnectivityResult.mobile ||
      result == ConnectivityResult.ethernet
    );

    print('Network change detected: $results (hasNetwork: $hasNetwork)');

    if (hasNetwork) {
      // Network became available - try reconnection if needed
      if (!_connectionService.isConnected &&
          _connectionService.hasServerInfo &&
          !_offlineService.isManualOfflineModeEnabled) {
        print('Network available and not connected - attempting reconnection...');
        _connectionService.tryRestoreConnection();
      }
    }
  }

  Future<void> _determineInitialScreen() async {
    // Ensure offline service is initialized before checking its state
    await _offlineService.initialize();
    
    // Try to restore previous connection
    final restored = await _connectionService.tryRestoreConnection();

    // If restore failed, make sure we load server info from storage
    // (tryRestoreConnection sets _serverInfo, but we want to be sure)
    if (!restored) {
      await _connectionService.loadServerInfoFromStorage();
    }

    setState(() {
      if (restored) {
        // Connection restored successfully - go to main app
        _initialScreen = const MainNavigationScreen();
      } else if (_connectionService.serverInfo != null) {
        // Has saved server info but couldn't connect
        // Notify connection lost (will auto-enable auto offline mode)
        // User can still use downloaded content and app will auto-reconnect when possible
        _offlineService.notifyConnectionLost();
        _initialScreen = const MainNavigationScreen();
      } else {
        // No saved connection - go to welcome/setup flow
        _initialScreen = const WelcomeScreen();
      }
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ariami',
      navigatorKey: _navigatorKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: _isLoading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _initialScreen,
      routes: {
        '/setup/tailscale': (context) => const TailscaleCheckScreen(),
        '/setup/scanner': (context) => const QRScannerScreen(),
        '/setup/permissions': (context) => const PermissionsScreen(),
        '/main': (context) => const MainNavigationScreen(),
        '/reconnect': (context) => const ReconnectScreen(),
      },
    );
  }
}
