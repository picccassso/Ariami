import 'package:flutter/material.dart';
import 'utils/constants.dart';
import 'screens/welcome_screen.dart';
import 'screens/tailscale_check_screen.dart';
import 'screens/folder_selection_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/desktop_state_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final DesktopStateService _stateService = DesktopStateService();
  bool _isLoading = true;
  bool _setupComplete = false;

  @override
  void initState() {
    super.initState();
    _checkSetupState();
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
