import 'package:flutter/material.dart';
import 'utils/constants.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/tailscale_check_screen.dart';
import 'screens/folder_selection_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BMA Desktop',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const SplashScreen(),
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/tailscale-check': (context) => const TailscaleCheckScreen(),
        '/folder-selection': (context) => const FolderSelectionScreen(),
        '/connection': (context) => const ConnectionScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}
