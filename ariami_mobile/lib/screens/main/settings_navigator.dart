import 'package:flutter/material.dart';
import 'settings_screen.dart';
import '../settings/connection_settings_screen.dart';
import '../settings/downloads_screen.dart';
import '../settings/import_export_screen.dart';
import '../settings/quality_settings_screen.dart';
import '../settings/streaming_stats_screen.dart';

/// A navigator key for the settings tab's nested navigation
final GlobalKey<NavigatorState> settingsNavigatorKey = GlobalKey<NavigatorState>();

/// Wrapper widget that provides nested navigation for the Settings tab.
/// This allows detail screens to be shown within the tab
/// while keeping the bottom navigation bar and mini player visible.
class SettingsNavigator extends StatelessWidget {
  const SettingsNavigator({super.key, this.onBackAtRoot});

  /// Called when user presses back at the root of this navigator
  final VoidCallback? onBackAtRoot;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final navigator = settingsNavigatorKey.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        } else {
          onBackAtRoot?.call();
        }
      },
      child: Navigator(
        key: settingsNavigatorKey,
        initialRoute: '/',
        onGenerateRoute: (settings) {
          Widget page;

          switch (settings.name) {
            case '/':
              page = const SettingsScreen();
              break;
            case '/connection':
              page = const ConnectionSettingsScreen();
              break;
            case '/downloads':
              page = const DownloadsScreen();
              break;
            case '/stats':
              page = const StreamingStatsScreen();
              break;
            case '/import-export':
              page = const ImportExportScreen();
              break;
            case '/quality':
              page = const QualitySettingsScreen();
              break;
            // Add more routes here as settings sub-screens are added
            default:
              page = const SettingsScreen();
          }

          return MaterialPageRoute(
            builder: (context) => page,
            settings: settings,
          );
        },
      ),
    );
  }
}
