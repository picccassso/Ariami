import 'package:flutter/material.dart';

import '../../utils/constants.dart';

Future<Map<String, String>?> showChangePasswordDialog(
  BuildContext context, {
  String? initialUsername,
}) {
  final usernameController = TextEditingController(text: initialUsername);
  final passwordController = TextEditingController();
  String? dialogError;

  return showDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceBlack,
            title: const Text(
              'Change User Password',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      labelStyle: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      labelStyle: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
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
                      dialogError = 'Username and new password are required.';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    <String, String>{
                      'username': username,
                      'newPassword': password,
                    },
                  );
                },
                child: const Text('Change Password'),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(() {
    usernameController.dispose();
    passwordController.dispose();
  });
}
