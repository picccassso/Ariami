import 'package:flutter/material.dart';

import 'app_local_data_reset.dart';
import '../screens/welcome_screen.dart';
import '../services/api/connection_service.dart';

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
            // Grab the root navigator before the pop: once the dialog route is
            // disposed this context unmounts and can no longer navigate.
            final rootNavigator = Navigator.of(context, rootNavigator: true);
            Navigator.of(context).pop();
            disconnectServerAndClearData(rootNavigator);
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

/// Navigates to the welcome screen immediately, then disconnects from the
/// server and clears local data in the background.
Future<void> disconnectServerAndClearData(NavigatorState rootNavigator) async {
  final userId = ConnectionService().userId;

  // Navigate first: the wipe can take seconds (server disconnect request,
  // deleting downloads/caches) and must not hold the user on the old screen.
  rootNavigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    (route) => false,
  );

  try {
    await clearAllLocalUserData(userId: userId);
  } catch (_) {
    // Reset runs each cleanup step independently. A local-store failure should
    // not trap the user on a stale server after it has been forgotten.
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
