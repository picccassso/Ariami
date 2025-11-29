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

// Global audio handler instance - accessible throughout the app
// Nullable because initialization might fail on some devices
BmaAudioHandler? audioHandler;

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
      androidNotificationChannelId: 'com.example.bma_mobile.audio',
      androidNotificationChannelName: 'BMA Music Playback',
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
        print('[Main] Step 4: Builder called - creating BmaAudioHandler...');
        return BmaAudioHandler();
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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _isLoading = true;
  Widget? _initialScreen;
  StreamSubscription<bool>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _determineInitialScreen();
    _listenToConnectionChanges();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  /// Listen for connection state changes to navigate to reconnect screen
  void _listenToConnectionChanges() {
    _connectionSubscription = _connectionService.connectionStateStream.listen(
      (isConnected) {
        if (!isConnected && _connectionService.hasServerInfo) {
          // Connection lost but we have server info - navigate to reconnect screen
          print('Connection lost - navigating to reconnect screen');
          _navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/reconnect',
            (route) => false,
          );
        }
      },
    );
  }

  Future<void> _determineInitialScreen() async {
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
        // Has saved server info but couldn't connect - go to reconnect screen
        _initialScreen = const ReconnectScreen();
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
      title: 'BMA Mobile',
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
