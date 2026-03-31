import 'package:flutter/material.dart';

Future<bool?> showDeleteAlbumDialog(
  BuildContext context, {
  required String albumName,
  required int songCount,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $albumName'),
      content: Text(
        'Are you sure you want to delete $songCount downloaded song${songCount != 1 ? 's' : ''} from "$albumName"? This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
