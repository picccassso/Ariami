import 'package:flutter/material.dart';

/// Banner shown on an album/playlist screen that only exists as an offline copy.
class OfflineCopyBanner extends StatelessWidget {
  final String itemType;

  const OfflineCopyBanner({super.key, required this.itemType});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        'Offline copy: this $itemType is no longer available on the server.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// One-time notice that an offline copy outlived its server item. Resolves to
/// true when the user chose to remove the download(s).
Future<bool> showOfflineCopyNotice(
  BuildContext context, {
  required String itemType,
  required String removeLabel,
}) async {
  final remove = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Offline copy kept'),
      content: Text(
        'Just a heads up - this $itemType has been deleted from the server.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep offline copy'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(removeLabel),
        ),
      ],
    ),
  );
  return remove == true;
}

/// Confirmation before deleting an album/playlist's downloaded files.
Future<bool> confirmRemoveDownloads(
  BuildContext context, {
  required String name,
  required String itemType,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Remove downloads for "$name"?'),
      content: Text(
        'This deletes the downloaded files for this $itemType from your '
        'device. You can download it again anytime.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            'Remove',
            style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}
