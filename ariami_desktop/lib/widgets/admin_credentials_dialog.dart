import 'package:flutter/material.dart';

import '../models/admin_credentials.dart';

/// Shows admin login dialog; returns credentials or null if cancelled.
Future<AdminCredentials?> showAdminCredentialsDialog(
    BuildContext context) async {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  String? dialogError;

  final credentials = await showDialog<AdminCredentials>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Admin Authentication'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
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
