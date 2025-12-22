import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'utils/constants.dart';
import 'screens/welcome_screen.dart';
import 'screens/tailscale_check_screen.dart';
import 'screens/folder_selection_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/desktop_state_service.dart';
import 'services/system_tray_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize window manager for close interception
  await windowManager.ensureInitialized();
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(900, 700),
    minimumSize: Size(600, 500),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  // IMPORTANT: Set prevent close BEFORE runApp to avoid race condition
  await windowManager.setPreventClose(true);
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  final DesktopStateService _stateService = DesktopStateService();
  final SystemTrayService _trayService = SystemTrayService();
  bool _isLoading = true;
  bool _setupComplete = false;
  bool _startupComplete = false; // Guards against early window close events

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Initialize system tray with error handling
    // This can fail when launched from Finder due to path resolution issues
    try {
      await _trayService.initialize();
    } catch (e) {
      print('[Main] Warning: Failed to initialize system tray: $e');
      // Continue without tray - app should still work
    }

    // Check setup state
    await _checkSetupState();

    // Allow hide-to-tray after a delay
    // This prevents phantom window close events during startup from hiding the app
    Future.delayed(const Duration(seconds: 3), () {
      _startupComplete = true;
      print('[Main] Startup complete - hide-to-tray now enabled');
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _trayService.dispose();
    super.dispose();
  }

  /// Intercept window close event - hide to tray instead of quitting.
  @override
  void onWindowClose() async {
    // Ignore close events during startup to prevent phantom events from Finder/Spotlight
    if (!_startupComplete) {
      print('[Window] Ignoring close event during startup protection period');
      return;
    }
    print('[Window] Close intercepted - hiding to tray');
    // Hide window to tray instead of closing
    await _trayService.hideWindow();
  }

  Future<void> _checkSetupState() async {
    final setupComplete = await _stateService.isSetupComplete();
    setState(() {
      _setupComplete = setupComplete;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BMA Desktop',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: _isLoading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _setupComplete
              ? const DashboardScreen()
              : const WelcomeScreen(),
      routes: {
        '/tailscale-check': (context) => const TailscaleCheckScreen(),
        '/folder-selection': (context) => const FolderSelectionScreen(),
        '/connection': (context) => const ConnectionScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}
