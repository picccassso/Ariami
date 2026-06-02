import 'package:flutter/material.dart';

import '../../models/server_info.dart';
import '../../services/api/connection_service.dart';

/// Routes to the correct setup destination for a resolved [serverInfo].
///
/// Shared by the QR scanner and the manual-entry fallback so both flows behave
/// identically once a [ServerInfo] is known:
/// - server has users (auth required) -> login screen
/// - server has no users (legacy mode) -> register screen (first account)
/// - otherwise -> connect directly and continue to permissions
///
/// Navigation uses `pushReplacementNamed` so the originating setup screen is not
/// left on the stack. Throws on connection failure so the caller can surface the
/// error (the camera/form state is owned by the caller).
Future<void> routeForServerInfo(
  BuildContext context,
  ServerInfo serverInfo,
  ConnectionService connectionService,
) async {
  final requiresAuth = serverInfo.authRequired && !serverInfo.legacyMode;

  if (requiresAuth) {
    Navigator.pushReplacementNamed(
      context,
      '/auth/login',
      arguments: serverInfo,
    );
    return;
  }

  if (serverInfo.legacyMode) {
    // First account must be created before access.
    Navigator.pushReplacementNamed(
      context,
      '/auth/register',
      arguments: serverInfo,
    );
    return;
  }

  // Server doesn't require auth - connect directly.
  await connectionService.connectToServer(serverInfo);

  if (context.mounted) {
    Navigator.pushReplacementNamed(context, '/setup/permissions');
  }
}
