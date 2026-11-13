import 'package:ariami_core/models/library_curation.dart';
import 'package:flutter/material.dart';

import '../../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../../widgets/settings/option_sheet.dart';

/// Opens a modal bottom sheet allowing the user to switch between
/// [LibraryCurationMode.full] and [LibraryCurationMode.curated].
Future<LibraryCurationMode?> showCurationModeSheet(
  BuildContext context, {
  required LibraryCurationMode currentMode,
}) {
  return showAriamiSheet<LibraryCurationMode>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    header: const AriamiSheetHeader(
      title: 'Library Mode',
      leading: Icon(Icons.tune_rounded),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OptionSheetTile(
          icon: Icons.all_inclusive_rounded,
          title: 'Include Everything',
          subtitle:
              'Show the full server catalog and new music automatically. '
              'Exclude specific artists, albums, or songs anytime.',
          selected: currentMode == LibraryCurationMode.full,
          onTap: () => Navigator.of(context).pop(LibraryCurationMode.full),
        ),
        OptionSheetTile(
          icon: Icons.tune_rounded,
          title: 'Curated Mode',
          subtitle:
              'Start clean and hand-pick only the artists, albums, server '
              'playlists, and songs you want in your library.',
          selected: currentMode == LibraryCurationMode.curated,
          onTap: () => Navigator.of(context).pop(LibraryCurationMode.curated),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}
