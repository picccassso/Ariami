import 'package:flutter/material.dart';
import 'utils/constants.dart';
import 'screens/welcome_screen.dart';
import 'screens/setup/tailscale_check_screen.dart';
import 'screens/setup/qr_scanner_screen.dart';
import 'screens/setup/permissions_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/reconnect_screen.dart';
import 'services/api/connection_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ConnectionService _connectionService = ConnectionService();
  bool _isLoading = true;
  Widget? _initialScreen;

  @override
  void initState() {
    super.initState();
    _determineInitialScreen();
  }

  Future<void> _determineInitialScreen() async {
    // Try to restore previous connection
    final restored = await _connectionService.tryRestoreConnection();

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
