import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';
import 'screens/tailscale_check_screen.dart';
import 'screens/folder_selection_screen.dart';
import 'screens/scanning_screen.dart';
import 'screens/qr_code_screen.dart';
import 'screens/dashboard_screen.dart';
import 'utils/constants.dart';

void main() {
  // Get the initial route from the browser URL to avoid transition animation on refresh
  final path = Uri.base.path;
  final validRoutes = {'/', '/tailscale-check', '/folder-selection', '/scanning', '/qr-code', '/dashboard'};
  final initialRoute = validRoutes.contains(path) ? path : '/';
  
  runApp(BmaWebApp(initialRoute: initialRoute));
}

class BmaWebApp extends StatelessWidget {
  final String initialRoute;
  
  const BmaWebApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BMA CLI',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      routes: {
        '/': (context) => const WelcomeScreen(),
        '/tailscale-check': (context) => const TailscaleCheckScreen(),
        '/folder-selection': (context) => const FolderSelectionScreen(),
        '/scanning': (context) => const ScanningScreen(),
        '/qr-code': (context) => const QRCodeScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}
