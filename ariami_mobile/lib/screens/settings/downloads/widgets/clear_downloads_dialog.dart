import 'package:flutter/material.dart';

Future<bool?> showClearDownloadsDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Clear All Downloads'),
      content: const Text(
        'Are you sure you want to delete all downloaded songs? This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete All', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
