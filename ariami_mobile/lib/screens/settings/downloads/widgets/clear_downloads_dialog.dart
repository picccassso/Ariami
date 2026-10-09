import 'package:flutter/material.dart';

import '../../../../widgets/common/confirm_dialog.dart';

Future<bool?> showClearDownloadsDialog(BuildContext context) {
  return showConfirmDialog(
    context,
    title: 'Clear All Downloads',
    message:
        'Are you sure you want to delete all downloaded songs? This action cannot be undone.',
    confirmLabel: 'Delete All',
    destructive: true,
  );
}
