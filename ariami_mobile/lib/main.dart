import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'screens/welcome_screen.dart';
import 'screens/setup/tailscale_check_screen.dart';
import 'screens/setup/qr_scanner_screen.dart';
import 'screens/setup/manual_server_entry_screen.dart';
import 'screens/setup/permissions_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/reconnect_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'models/server_info.dart';
import 'services/api/connection_service.dart';
import 'services/audio/audio_handler.dart';
import 'services/audio/equalizer_service.dart';
import 'services/offline/offline_playback_service.dart';
import 'services/profile_image_service.dart';
import 'services/download/background_download_notifier.dart';
import 'services/download/download_manager.dart';
import 'widgets/download/global_download_chrome_visibility.dart';
import 'services/cache/cache_manager.dart';
import 'services/stats/streaming_stats_service.dart';
import 'services/stats/account_stats_service.dart';
import 'services/quality/quality_settings_service.dart';
import 'services/quality/network_monitor_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'services/theme_service.dart';
import 'utils/server_disconnect.dart';
import 'utils/shared_preferences_cache.dart';

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

    // Configure the system audio session for music playback. This establishes
    // the correct Android audio attributes and an AUDIOFOCUS_GAIN request, which
    // is what makes the OS route hardware/Bluetooth (AVRCP) media-key events to
    // our MediaSession. Without it, notification controls still work (they fire
    // PendingIntents directly) but headset play/pause/skip buttons are routed to
    // whichever app last held audio focus instead of Ariami.
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      print('[Main] ✅ AudioSession configured for music playback');
    } catch (e) {
      print('[Main] ⚠️ Failed to configure AudioSession: $e');
    }

    // Initialize equalizer settings in the background after audio is ready.
    // ignore: avoid_print
    print('[Main] Starting EqualizerService initialization...');
    unawaited(EqualizerService().initialize());
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
  await initializeSharedPrefs();

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
  final ProfileImageService _profileImageService = ProfileImageService();
  final DownloadManager _downloadManager = DownloadManager();
  final CacheManager _cacheManager = CacheManager();
  final StreamingStatsService _statsService = StreamingStatsService();
  final QualitySettingsService _qualityService = QualitySettingsService();
  final NetworkMonitorService _networkMonitor = NetworkMonitorService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
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
  bool _downloadsPausedForLifecycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAndDetermineScreen();
    _listenToConnectionChanges();
    _listenToSessionExpiry();
    _listenToNetworkChanges();
  }

  /// Initialize the bare minimum needed to choose a screen, show it, then warm
  /// everything else in the background.
  Future<void> _initializeAndDetermineScreen() async {
    // Critical path: only auth info and offline state are needed to decide
    // which screen to show first.
    await _connectionService.loadAuthInfo();
    await _offlineService.initialize();

    // Pick and render the initial screen as soon as possible.
    await _determineInitialScreen();

    // Warm the remaining services once the UI is already on screen.
    unawaited(_initializeDeferredServices());
  }

  /// Initialize non-critical services after the first screen is shown.
  ///
  /// None of these gate the initial-screen decision, and they are independent
  /// of one another, so they run concurrently instead of blocking startup with
  /// a chain of sequential awaits.
  Future<void> _initializeDeferredServices() async {
    await Future.wait([
      // Download manager (also initializes quality settings internally)
      _downloadManager.initialize(),
      // Artwork/song cache
      _cacheManager.initialize(),
      // Streaming play-stats
      _statsService.initialize(),
      // Quality settings (idempotent; shared with the download manager)
      _qualityService.initialize(),
      // Network-type monitor for quality-based streaming
      _networkMonitor.initialize(),
      // Profile image, pre-cached before the Settings tab is opened
      _profileImageService.initialize(),
    ]);

    // Cross-device stats sync builds on the stats service, so it starts once
    // that is ready. Fire-and-forget: it manages its own connectivity.
    unawaited(AccountStatsService().initialize());

    GlobalDownloadChromeVisibility.instance.startListening();

    _startupInterruptedDownloadCount =
        _downloadManager.getInterruptedDownloadCount();
    _startupAutoResumeInterruptedOnLaunch =
        _downloadManager.getAutoResumeInterruptedOnLaunch();

    print(
        '[Main] Deferred services initialized (Download, Cache, Stats, Network, Quality, Profile)');

    if (!mounted) return;

    // Download recovery depends on the download manager being initialized, so
    // it runs here rather than during initial-screen selection.
    if (_startupAutoResumeInterruptedOnLaunch) {
      _maybeAutoResumeStartupDownloads();
    } else {
      _maybePromptStartupDownloadRecovery();
    }
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
    // Persist any queued listening events before the OS may kill the app.
    if (state != AppLifecycleState.resumed) {
      unawaited(AccountStatsService().flush());
    }

    // Swiping the app away transitions to detached on supported platforms.
    // When the native backend is carrying downloads, its foreground service
    // keeps this process (and the queue loop) alive — leave the queue running
    // instead of pausing it. Persistence is continuous, so if the OS kills
    // the process anyway, launch reconciliation recovers the state.
    if (state == AppLifecycleState.detached) {
      _downloadManager.setAppInForeground(false);
      if (_canContinueDownloadsInBackground()) {
        unawaited(BackgroundDownloadNotifier.instance.onAppBackgrounded());
      } else {
        unawaited(_downloadManager.pauseDownloadsForAppClosure());
      }
      return;
    }

    // `inactive` (and `hidden`) fire for transient occlusions — the
    // notification shade, heads-up notifications, permission dialogs, app
    // switcher peeks — where tearing down every active download only to
    // restart it moments later causes a queue-update storm. Only a real
    // background transition (`paused`) touches downloads.
    if (state == AppLifecycleState.paused) {
      _downloadManager.setAppInForeground(false);
      if (_canContinueDownloadsInBackground()) {
        // Android: hand active transfers to the WorkManager backend so the
        // queue keeps downloading in the background instead of pausing. The
        // batch notification service starts first so workers see it holding
        // the foreground slot and skip their own per-song notifications.
        unawaited(() async {
          await BackgroundDownloadNotifier.instance.onAppBackgrounded();
          await _downloadManager.continueDownloadsInBackground();
        }());
      } else {
        _downloadsPausedForLifecycle = true;
        unawaited(_downloadManager.pauseDownloadsForLifecycleInterruption());
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _downloadManager.setAppInForeground(true);
      unawaited(BackgroundDownloadNotifier.instance.onAppResumed());
      _triggerResumeReconnectIfNeeded();
      if (_downloadsPausedForLifecycle) {
        _downloadsPausedForLifecycle = false;
        unawaited(_downloadManager.resumeLifecycleInterruptedDownloads());
      }
    }
  }

  /// Background download continuation rides on the Android WorkManager
  /// backend; other platforms (and idle queues) keep the pause/resume flow.
  bool _canContinueDownloadsInBackground() {
    return Platform.isAndroid && _downloadManager.hasActiveOrPendingDownloads;
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

    final context = _navigatorKey.currentContext;
    if (context != null) {
      navigateToWelcomeScreen(context);
    }
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

    // Load saved server info from storage. This only touches local storage, so
    // it's fast - unlike the network reconnect, which we defer to the
    // background so the UI is never gated on a socket timeout.
    await _connectionService.loadServerInfoFromStorage();

    setState(() {
      // A saved server means the user has set the app up before, so drop them
      // straight into the app (offline-capable) while we reconnect in the
      // background. Otherwise start the welcome/setup flow.
      _initialScreen = _connectionService.serverInfo != null
          ? const MainNavigationScreen()
          : const WelcomeScreen();
      _isLoading = false;
    });

    if (_connectionService.serverInfo != null) {
      unawaited(_restoreConnectionInBackground());
    }
  }

  /// Restore the saved server connection without blocking the UI.
  ///
  /// Short-circuits the socket-probe round trip entirely when there is no
  /// network, so offline launches drop straight into auto-offline mode instead
  /// of waiting out connect timeouts. On any failure we enter auto-offline so
  /// downloaded content stays usable and the app auto-reconnects when possible.
  Future<void> _restoreConnectionInBackground() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    final hasNetwork = connectivityResults.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet);

    if (!hasNetwork) {
      _offlineService.notifyConnectionLost();
      // The first connect never happened, so the heartbeat/auto-reconnect loop
      // was never started. Start it explicitly so the app recovers on its own
      // instead of staying stuck offline until a network change or restart.
      _connectionService.ensureReconnectLoopRunning();
      return;
    }

    final restored = await _connectionService.tryRestoreConnection();
    if (!restored) {
      _offlineService.notifyConnectionLost();
      _connectionService.ensureReconnectLoopRunning();
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
    await _downloadManager.resumeInterruptedDownloads();
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

    await _downloadManager.resumeInterruptedDownloads();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        return MaterialApp(
          title: 'Ariami',
          navigatorKey: _navigatorKey,
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
            '/setup/manual': (context) => const ManualServerEntryScreen(),
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
