import 'package:flutter/material.dart';

import '../../../../widgets/common/confirm_dialog.dart';

Future<bool?> showDeleteAlbumDialog(
  BuildContext context, {
  required String albumName,
  required int songCount,
}) {
  return showConfirmDialog(
    context,
    title: 'Delete $albumName',
    message:
        'Are you sure you want to delete $songCount downloaded song${songCount != 1 ? 's' : ''} from "$albumName"? This action cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  );
}
