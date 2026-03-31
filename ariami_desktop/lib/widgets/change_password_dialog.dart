import 'package:flutter/material.dart';

/// Result of [showChangePasswordDialog].
class ChangePasswordPayload {
  const ChangePasswordPayload({
    required this.username,
    required this.newPassword,
  });

  final String username;
  final String newPassword;
}

/// Shows change-password dialog; returns payload or null if cancelled.
Future<ChangePasswordPayload?> showChangePasswordDialog(
  BuildContext context, {
  String? initialUsername,
}) async {
  final usernameController = TextEditingController(text: initialUsername);
  final passwordController = TextEditingController();
  String? dialogError;

  final payload = await showDialog<ChangePasswordPayload>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Change User Password'),
            content: SizedBox(
              width: 400,
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
                    decoration:
                        const InputDecoration(labelText: 'New Password'),
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
                  final newPassword = passwordController.text;
                  if (username.isEmpty || newPassword.isEmpty) {
                    setDialogState(() {
                      dialogError = 'Username and new password are required.';
                    });
                    return;
                  }

                  Navigator.of(dialogContext).pop(
                    ChangePasswordPayload(
                      username: username,
                      newPassword: newPassword,
                    ),
                  );
                },
                child: const Text('Change Password'),
              ),
            ],
          );
        },
      );
    },
  );

  usernameController.dispose();
  passwordController.dispose();
  return payload;
}
