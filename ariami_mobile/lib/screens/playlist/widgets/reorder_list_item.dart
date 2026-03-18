import 'package:flutter/material.dart';
import '../../../models/api_models.dart';

/// Reorder mode list item with drag handle
class ReorderListItem extends StatelessWidget {
  /// The song to display
  final SongModel song;

  /// Index in the list (for display number)
  final int index;

  /// Callback when remove button is pressed
  final VoidCallback? onRemove;

  const ReorderListItem({
    super.key,
    required this.song,
    required this.index,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('reorder_${song.id}'),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
          onPressed: onRemove,
        ),
      ),
    );
  }
}
