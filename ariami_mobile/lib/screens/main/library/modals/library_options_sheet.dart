import 'package:flutter/material.dart';

import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../library_controller.dart';

/// Bottom sheet content displaying view options and actions for the library.
class LibraryOptionsSheet extends StatelessWidget {
  final LibraryController controller;
  final bool isOffline;
  final VoidCallback onRefresh;

  const LibraryOptionsSheet({
    super.key,
    required this.controller,
    required this.isOffline,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.arrow_circle_down_rounded),
              title: const Text('Downloaded Only'),
              value: state.showDownloadedOnly,
              onChanged: (_) => controller.toggleShowDownloadedOnly(),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.grid_view_rounded),
              title: const Text('Grid View'),
              value: state.isGridView,
              onChanged: (_) => controller.toggleViewMode(),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.all_inclusive_rounded),
              title: const Text('Mix Playlists & Albums'),
              value: state.isMixedMode,
              onChanged: (_) => controller.toggleMixedMode(),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.playlist_add_check_rounded),
              title: const Text('Select Multiple'),
              onTap: () {
                Navigator.pop(context);
                controller.enterSelectionMode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Refresh Library'),
              enabled: !isOffline,
              onTap: isOffline
                  ? null
                  : () {
                      Navigator.pop(context);
                      onRefresh();
                    },
            ),
          ],
        );
      },
    );
  }
}

/// Shows the library options bottom sheet.
Future<void> showLibraryOptionsSheet({
  required BuildContext context,
  required LibraryController controller,
  required bool isOffline,
  required VoidCallback onRefresh,
}) {
  return showAriamiSheet<void>(
    context: context,
    header: const AriamiSheetHeader(
      title: 'Library Options',
      leading: Icon(Icons.tune_rounded),
    ),
    child: LibraryOptionsSheet(
      controller: controller,
      isOffline: isOffline,
      onRefresh: onRefresh,
    ),
  );
}
