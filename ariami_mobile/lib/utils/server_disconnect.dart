import 'package:flutter/material.dart';

import '../database/library_sync_database.dart';
import '../screens/welcome_screen.dart';
import '../services/api/connection_service.dart';
import '../services/cache/cache_manager.dart';
import '../services/download/download_manager.dart';
import '../services/offline/sync_service.dart';
import '../services/playlist_service.dart';
import '../services/theme_service.dart';

/// Shows the confirmation dialog for disconnecting from the server.
void showDisconnectServerDialog(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
      title: Text(
        'DISCONNECT SERVER',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      content: Text(
        'This will forget this server, sign you out, and remove downloaded music and cached server data from this phone. You will need to scan the QR code again to reconnect.',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(
            'CANCEL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            disconnectServerAndClearData(context);
          },
          child: const Text(
            'DISCONNECT & CLEAR DATA',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: Color(0xFFFF4B4B),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Replaces the entire navigation stack with the welcome/setup screen.
void navigateToWelcomeScreen(BuildContext context) {
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    (route) => false,
  );
}

/// Disconnects from the server, clears local data, and navigates to welcome.
Future<void> disconnectServerAndClearData(BuildContext context) async {
  try {
    await ConnectionService().disconnectAndForgetServer();
    await DownloadManager().clearAllDownloads();
    await CacheManager().clearAllCache();
    final libraryDatabase = await LibrarySyncDatabase.create();
    await libraryDatabase.clearAllData();
    await PlaylistService().clearAllPlaylistData();
    await SyncService().clearPendingActions();
    await ThemeService().setThemeSource(ThemeSource.darkNeutral);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server disconnected and local data cleared'),
        ),
      );
      navigateToWelcomeScreen(context);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error disconnecting: $e')),
      );
    }
  }
}

/// Styling for the disconnect server button used across auth and settings screens.
ButtonStyle disconnectServerButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF1A1A1A),
    foregroundColor: const Color(0xFFFF4B4B),
    elevation: 0,
    shape: const StadiumBorder(),
    side: BorderSide(color: const Color(0xFFFF4B4B).withValues(alpha: 0.2)),
  );
}
