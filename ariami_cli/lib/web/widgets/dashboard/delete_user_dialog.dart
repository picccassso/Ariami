import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';

Future<bool> showDeleteUserDialog(
  BuildContext context, {
  required ServerUserRow user,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('Delete User'),
        content: Text(
          'Delete "${user.username}" from this server?\n\n'
          'Their active sessions, including mobile sessions, will be logged '
          'out immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete User'),
          ),
        ],
      );
    },
  );

  return confirmed ?? false;
}
