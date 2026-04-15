import 'package:flutter/material.dart';

import '../models/admin_credentials.dart';
import '../services/desktop_state_service.dart';

/// Shows owner sign-in dialog; returns credentials or null if cancelled.
Future<AdminCredentials?> showAdminCredentialsDialog(
  BuildContext context, {
  String? ownerUsername,
}) async {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  String? dialogError;

  if (ownerUsername != null && ownerUsername.isNotEmpty) {
    usernameController.text = ownerUsername;
  }

  final credentials = await showDialog<AdminCredentials>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Owner Sign-In Required'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'This is required for Owner-only actions like Kick Device and Change Password.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Owner Username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Owner Password'),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _showOwnerRecoveryDialog(dialogContext),
                      child: const Text('Forgot owner password?'),
                    ),
                  ),
                  if (dialogError != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        dialogError!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final username = usernameController.text.trim();
                  final password = passwordController.text;
                  if (username.isEmpty || password.isEmpty) {
                    setDialogState(() {
                      dialogError = 'Username and password are required.';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    AdminCredentials(username: username, password: password),
                  );
                },
                child: const Text('Login'),
              ),
            ],
          );
        },
      );
    },
  );

  usernameController.dispose();
  passwordController.dispose();
  return credentials;
}

Future<void> _showOwnerRecoveryDialog(
  BuildContext context,
) async {
  final stateService = DesktopStateService();
  final usersPath = await stateService.getUsersFilePath();
  final sessionsPath = await stateService.getSessionsFilePath();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Recover Owner Access'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'If you forgot the Owner password, stop Ariami and remove local auth files. '
                'Then restart and create a new Owner account.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                'Mac terminal commands:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              SelectableText('rm -f "$sessionsPath"'),
              SelectableText('rm -f "$usersPath"'),
              const SizedBox(height: 12),
              const Text(
                'You can also follow RESET.md in the repository for a full reset guide.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
