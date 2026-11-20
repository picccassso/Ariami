import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/library_controller.dart';
import 'queue_intent.dart';

/// A hideable target: `album` / `playlist` / `artist` plus its id (the display
/// name, for an artist).
typedef HideTarget = ({String type, String targetId});

/// Hides one collection or a whole multi-selection, with an Undo.
///
/// Hiding is account-synced and the only other way back is the Hidden items
/// list in Settings, so the confirmation carries the undo rather than just
/// announcing what happened.
Future<void> hideCollections(
  BuildContext context,
  List<HideTarget> targets,
) async {
  if (targets.isEmpty) return;
  final library = context.read<LibraryController>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await library.hideItems(targets);
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Could not hide: $e')),
    );
    return;
  }
  showUndoToast(
    messenger,
    targets.length == 1
        ? 'Removed from your library'
        : '${targets.length} items removed from your library',
    onUndo: () => unhideAll(library, targets),
  );
}

/// Restores [targets]. Failures are swallowed deliberately: this runs from an
/// Undo whose SnackBar is already gone, so there is nowhere left to report to,
/// and the Settings list still holds anything that did not come back.
Future<void> unhideAll(
  LibraryController library,
  List<HideTarget> targets,
) async {
  for (final target in targets) {
    try {
      await library.unhideItem(target.type, target.targetId);
    } catch (_) {
      continue;
    }
  }
}

HideTarget albumHideTarget(String albumId) =>
    (type: HiddenMediaItem.albumType, targetId: albumId);

HideTarget playlistHideTarget(String playlistId) =>
    (type: HiddenMediaItem.playlistType, targetId: playlistId);

HideTarget artistHideTarget(String name) =>
    (type: HiddenMediaItem.artistType, targetId: name);
