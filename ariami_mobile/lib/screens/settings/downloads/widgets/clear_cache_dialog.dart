import 'package:flutter/material.dart';

import '../../../../widgets/common/confirm_dialog.dart';

Future<bool?> showClearCacheDialog(BuildContext context) {
  return showConfirmDialog(
    context,
    title: 'Clear Song Cache',
    message:
        'This will remove cached songs used for streaming. Artwork and explicitly downloaded songs will not be affected.',
    confirmLabel: 'Clear',
    destructive: true,
  );
}
