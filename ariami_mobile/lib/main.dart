import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/constants.dart';
import 'screens/welcome_screen.dart';
import 'screens/setup/tailscale_check_screen.dart';
import 'screens/setup/qr_scanner_screen.dart';
import 'screens/setup/permissions_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/reconnect_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'models/server_info.dart';
import 'services/api/connection_service.dart';
import 'services/audio/audio_handler.dart';
import 'services/offline/offline_playback_service.dart';
import 'services/download/download_manager.dart';
import 'services/cache/cache_manager.dart';
import 'services/stats/streaming_stats_service.dart';
import 'services/quality/quality_settings_service.dart';
import 'services/quality/network_monitor_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'services/theme_service.dart';

// Global audio handler instance - accessible throughout the app
// Nullable because initialization might fail on some devices
AriamiAudioHandler? audioHandler;

// Global SharedPreferences instance - pre-loaded for synchronous access
// This eliminates flicker in widgets that need persisted state on first build
late SharedPreferences sharedPrefs;

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
      androidNotificationOngoing:
          false, // Changed: Must be false when androidStopForegroundOnPause is false
      androidShowNotificationBadge: true,
      androidStopForegroundOnPause:
          false, // Keep service alive even when paused
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
    print(
        '[Main] audioHandler is: ${audioHandler != null ? "NOT NULL" : "NULL"}');
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

  // Pre-load SharedPreferences for synchronous access throughout the app
  // This eliminates flicker in widgets that need persisted state on first build
  sharedPrefs = await SharedPreferences.getInstance();

  // Initialize ThemeService after SharedPreferences is loaded
  ThemeService().init();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final ConnectionService _connectionService = ConnectionService();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final DownloadManager _downloadManager = DownloadManager();
  final CacheManager _cacheManager = CacheManager();
  final StreamingStatsService _statsService = StreamingStatsService();
  final QualitySettingsService _qualityService = QualitySettingsService();
  final NetworkMonitorService _networkMonitor = NetworkMonitorService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  bool _isLoading = true;
  Widget? _initialScreen;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<void>? _sessionExpiredSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _networkDebounceTimer;
  Future<void>? _resumeReconnectFuture;
  bool _startupRecoveryPromptShown = false;
  int _startupInterruptedDownloadCount = 0;
  bool _startupAutoResumeInterruptedOnLaunch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAndDetermineScreen();
    _listenToConnectionChanges();
    _listenToSessionExpiry();
    _listenToNetworkChanges();
  }

  /// Initialize services and determine initial screen (must be sequential)
  Future<void> _initializeAndDetermineScreen() async {
    await _initializeServices();
    await _determineInitialScreen();
  }

  /// Initialize background services
  Future<void> _initializeServices() async {
    // Load stored auth info (session token, userId, username) before connection attempt
    await _connectionService.loadAuthInfo();
    // Initialize offline playback service (listens to connection changes)
    await _offlineService.initialize();
    // Initialize download manager
    await _downloadManager.initialize();
    _startupInterruptedDownloadCount =
        _downloadManager.getInterruptedDownloadCount();
    _startupAutoResumeInterruptedOnLaunch =
        _downloadManager.getAutoResumeInterruptedOnLaunch();
    // Initialize cache manager for artwork and song caching
    await _cacheManager.initialize();
    // Initialize streaming stats service for play tracking
    await _statsService.initialize();
    // Initialize network monitor for quality-based streaming
    await _networkMonitor.initialize();
    // Initialize quality settings service
    await _qualityService.initialize();
    print(
        '[Main] Auth, Offline, Download, Cache, Stats, Network, and Quality services initialized');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionSubscription?.cancel();
    _sessionExpiredSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _networkDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Swiping the app away transitions to detached on supported platforms.
    if (state == AppLifecycleState.detached) {
      unawaited(_downloadManager.pauseDownloadsForAppClosure());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _triggerResumeReconnectIfNeeded();
    }
  }

  void _triggerResumeReconnectIfNeeded() {
    if (_resumeReconnectFuture != null) {
      return;
    }

    _resumeReconnectFuture = _attemptResumeReconnect().whenComplete(() {
      _resumeReconnectFuture = null;
    });
  }

  Future<void> _attemptResumeReconnect() async {
    if (_isLoading) {
      return;
    }

    if (_offlineService.isManualOfflineModeEnabled) {
      return;
    }

    final connectivityResults = await Connectivity().checkConnectivity();
    final hasNetwork = connectivityResults.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet);

    if (!hasNetwork) {
      return;
    }

    if (_connectionService.isConnected) {
      return;
    }

    if (!_connectionService.hasServerInfo) {
      await _connectionService.loadServerInfoFromStorage();
      if (!_connectionService.hasServerInfo) {
        return;
      }
    }

    print('App resumed while disconnected - attempting immediate reconnect...');
    final restored = await _connectionService.tryRestoreConnection();
    if (!restored) {
      print(
        'Immediate reconnect on resume failed; automatic retries remain active',
      );
    }
  }

  /// Listen for connection state changes
  void _listenToConnectionChanges() {
    _connectionSubscription = _connectionService.connectionStateStream.listen(
      (isConnected) {
        if (!isConnected && _connectionService.hasServerInfo) {
          // Connection lost - check offline mode state
          if (_offlineService.isManualOfflineModeEnabled) {
            // Manual offline mode - user chose to go offline, stay in app
            print(
                'Connection lost but manual offline mode enabled - staying in app');
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

  /// Listen for session expiry events (401 from server)
  void _listenToSessionExpiry() {
    _sessionExpiredSubscription =
        _connectionService.sessionExpiredStream.listen(
      (_) {
        unawaited(_navigateToLoginFromSessionExpiry());
      },
    );
  }

  Future<void> _navigateToLoginFromSessionExpiry() async {
    print('Session expired or auth required - navigating to login screen');
    await _connectionService.loadServerInfoFromStorage();

    final serverInfo = _connectionService.serverInfo;
    if (serverInfo != null) {
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/auth/login',
        (route) => false,
        arguments: serverInfo,
      );
      return;
    }

    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/',
      (route) => false,
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
        result == ConnectivityResult.ethernet);

    print('Network change detected: $results (hasNetwork: $hasNetwork)');

    if (hasNetwork) {
      // Network became available - try reconnection if needed
      if (!_connectionService.isConnected &&
          _connectionService.hasServerInfo &&
          !_offlineService.isManualOfflineModeEnabled) {
        print(
            'Network available and not connected - attempting reconnection...');
        _connectionService.tryRestoreConnection();
      }
    }
  }

  Future<void> _determineInitialScreen() async {
    // Ensure offline service is initialized before checking its state
    await _offlineService.initialize();

    // If manual offline mode was persisted, skip connection restoration
    if (_offlineService.isManualOfflineModeEnabled) {
      print('Manual offline mode persisted - skipping connection restoration');
      await _connectionService.loadServerInfoFromStorage();
      setState(() {
        _initialScreen = const MainNavigationScreen();
        _isLoading = false;
      });
      return;
    }

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

    if (_startupAutoResumeInterruptedOnLaunch) {
      _maybeAutoResumeStartupDownloads();
    } else {
      _maybePromptStartupDownloadRecovery();
    }
  }

  void _maybeAutoResumeStartupDownloads() {
    if (_startupInterruptedDownloadCount <= 0 || _isLoading) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_autoResumeStartupDownloads());
    });
  }

  Future<void> _autoResumeStartupDownloads() async {
    if (!mounted) return;
    final resumed = await _downloadManager.resumeInterruptedDownloads();
    if (!mounted || resumed <= 0) return;

    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          'Auto-resumed $resumed paused download${resumed == 1 ? '' : 's'}.',
        ),
      ),
    );
  }

  void _maybePromptStartupDownloadRecovery() {
    if (_startupRecoveryPromptShown ||
        _startupInterruptedDownloadCount <= 0 ||
        _isLoading) {
      return;
    }
    _startupRecoveryPromptShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showStartupDownloadRecoveryDialog());
    });
  }

  Future<void> _showStartupDownloadRecoveryDialog() async {
    if (!mounted) return;
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    final pausedCount = _startupInterruptedDownloadCount;
    final shouldResume = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Continue Downloads?'),
        content: Text(
          '$pausedCount download${pausedCount == 1 ? '' : 's'} were paused when the app was closed. Continue now or keep them paused?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Paused'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue Downloads'),
          ),
        ],
      ),
    );

    if (!mounted || shouldResume != true) return;

    final resumed = await _downloadManager.resumeInterruptedDownloads();
    if (!mounted || resumed <= 0) return;

    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          'Resumed $resumed paused download${resumed == 1 ? '' : 's'}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        return MaterialApp(
          title: 'Ariami',
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _scaffoldMessengerKey,
          theme: ThemeService().lightTheme,
          darkTheme: ThemeService().darkTheme,
          themeMode: ThemeService().themeMode,
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
        '/auth/login': (context) {
          final serverInfo =
              ModalRoute.of(context)!.settings.arguments as ServerInfo;
          return LoginScreen(serverInfo: serverInfo);
        },
        '/auth/register': (context) {
          final serverInfo =
              ModalRoute.of(context)!.settings.arguments as ServerInfo;
          return RegisterScreen(serverInfo: serverInfo);
        },
      },
    );
      },
    );
  }
}
