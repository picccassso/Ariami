import 'package:flutter/material.dart';

import 'app_local_data_reset.dart';
import '../screens/welcome_screen.dart';
import '../services/api/connection_service.dart';
import '../widgets/common/confirm_dialog.dart';
import 'constants.dart';

Future<void> showDisconnectServerDialog(BuildContext context) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Disconnect server',
    message: 'This will forget this server, sign you out, and remove '
        'downloaded music and cached server data from this phone. You will '
        'need to scan the QR code again to reconnect.',
    confirmLabel: 'Disconnect & clear data',
    destructive: true,
  );
  if (confirmed != true || !context.mounted) return;
  disconnectServerAndClearData(Navigator.of(context, rootNavigator: true));
}

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

ButtonStyle disconnectServerButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF1A1A1A),
    foregroundColor: const Color(0xFFFF4B4B),
    elevation: 0,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppTheme.tileRadius))),
    side: BorderSide(color: const Color(0xFFFF4B4B).withValues(alpha: 0.2)),
  );
}
