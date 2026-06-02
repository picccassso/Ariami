import 'package:flutter/material.dart';

import '../../utils/constants.dart';

class CreateUserPayload {
  const CreateUserPayload({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;
}

Future<CreateUserPayload?> showCreateUserDialog(BuildContext context) async {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  String? dialogError;

  final payload = await showDialog<CreateUserPayload>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceBlack,
            title: const Text('Create User'),
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
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                    ),
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
                  if (password != confirmPasswordController.text) {
                    setDialogState(() {
                      dialogError = 'Passwords do not match.';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    CreateUserPayload(username: username, password: password),
                  );
                },
                child: const Text('Create User'),
              ),
            ],
          );
        },
      );
    },
  );

  usernameController.dispose();
  passwordController.dispose();
  confirmPasswordController.dispose();
  return payload;
}
