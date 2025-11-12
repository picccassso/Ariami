import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'utils/constants.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/setup/tailscale_check_screen.dart';
import 'screens/setup/qr_scanner_screen.dart';
import 'screens/setup/permissions_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'services/app_state_service.dart';
import 'services/api/connection_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateService()),
        ChangeNotifierProvider(create: (_) => ConnectionService()),
      ],
      child: MaterialApp(
        title: 'BMA Mobile',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const SplashScreen(),
        routes: {
          '/welcome': (context) => const WelcomeScreen(),
          '/setup/tailscale': (context) => const TailscaleCheckScreen(),
          '/setup/scanner': (context) => const QRScannerScreen(),
          '/setup/permissions': (context) => const PermissionsScreen(),
          '/main': (context) => const MainNavigationScreen(),
        },
      ),
    );
  }
}
