import 'dart:async';

import 'package:flutter/material.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../theme/player_theme.dart';
import 'queue_intent.dart';

/// Removes the upcoming rows at [upcomingIndices] (parallel to [tracks]) and
/// offers Undo.
void removeUpcomingWithUndo(
  AudioController audio,
  ScaffoldMessengerState? messenger,
  List<int> upcomingIndices,
  List<Track> tracks,
) {
  final undo = audio.removeUpcomingAll(upcomingIndices);
  if (undo == null) return;
  showUndoToast(
    messenger,
    tracks.length == 1
        ? 'Removed "${tracks.single.title}"'
        : 'Removed ${tracks.length} songs',
    onUndo: () => unawaited(undo()),
  );
}

class QueueRemoveButton extends StatelessWidget {
  const QueueRemoveButton({
    super.key,
    required this.onPressed,
    this.iconSize = 19,
  });

  final VoidCallback onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Remove from queue',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      color: context.colors.textSecondary,
      onPressed: onPressed,
      icon: Icon(Icons.close_rounded, size: iconSize),
    );
  }
}
