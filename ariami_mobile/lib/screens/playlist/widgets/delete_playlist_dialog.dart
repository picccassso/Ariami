import 'package:flutter/material.dart';
import '../../../models/api_models.dart';

/// Result type for delete playlist dialog
enum DeletePlaylistAction {
  cancel,
  restore,
  permanent,
}

/// Dialog for deleting a playlist with import awareness
class DeletePlaylistDialog extends StatelessWidget {
  /// The playlist to delete
  final PlaylistModel playlist;

  /// Whether the playlist was imported from server
  final bool isImported;

  const DeletePlaylistDialog({
    super.key,
    required this.playlist,
    required this.isImported,
  });

  @override
  Widget build(BuildContext context) {
    if (isImported) {
      // Special dialog for imported playlists
      return AlertDialog(
        title: const Text('Delete Imported Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This playlist was imported from your server.'),
            const SizedBox(height: 12),
            const Text(
              'What would you like to do?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, DeletePlaylistAction.cancel),
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.pop(context, DeletePlaylistAction.restore),
            icon: const Icon(Icons.restore),
            label: const Text('Delete & Restore Original'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(context, DeletePlaylistAction.permanent),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Delete Permanently'),
          ),
        ],
      );
    } else {
      // Standard delete for regular playlists
      return AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Are you sure you want to delete "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, DeletePlaylistAction.cancel),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, DeletePlaylistAction.permanent),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      );
    }
  }
}

/// Shows the delete playlist dialog
Future<DeletePlaylistAction> showDeletePlaylistDialog(
  BuildContext context,
  PlaylistModel playlist, {
  required bool isImported,
}) async {
  final result = await showDialog<DeletePlaylistAction>(
    context: context,
    builder: (context) => DeletePlaylistDialog(
      playlist: playlist,
      isImported: isImported,
    ),
  );
  return result ?? DeletePlaylistAction.cancel;
}
