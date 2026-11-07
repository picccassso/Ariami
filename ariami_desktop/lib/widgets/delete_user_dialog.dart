import 'package:flutter/material.dart';
import '../utils/constants.dart';

import '../models/server_user_row.dart';

/// Confirms deleting [user], including immediate logout of active sessions.
Future<bool> showDeleteUserDialog(
  BuildContext context, {
  required ServerUserRow user,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Delete "${user.username}" from this server?\n\n'
          'If they are currently logged in (including on mobile), '
          'their session will be logged out immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.textPrimary,
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
