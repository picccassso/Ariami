import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';

/// What a click on a Play control should do, given the modifiers held with it.
///
/// Shift queues the tracks behind whatever is playing and cmd/ctrl slots them
/// in right after the current one, so every Play button doubles as the two
/// queue actions the right-click menu already offers. cmd is the modifier on
/// macOS, where ctrl-click is the platform's secondary click — the same split
/// the track list already uses for multi-select.
enum QueueIntent { play, addToQueue, playNext }

/// Reads the modifiers held right now.
///
/// Callers that resolve their tracks asynchronously must capture this *before*
/// awaiting: by the time an album's detail request comes back the keys are
/// usually released.
QueueIntent readQueueIntent() {
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isShiftPressed) return QueueIntent.addToQueue;
  final playNext = defaultTargetPlatform == TargetPlatform.macOS
      ? keyboard.isMetaPressed
      : keyboard.isControlPressed;
  return playNext ? QueueIntent.playNext : QueueIntent.play;
}

/// Runs [intent] against [tracks], returning whether it replaced plain
/// playback. Returns false for an unmodified click — and for an empty
/// collection, which has nothing to queue — so callers fall through to their
/// own play behaviour.
bool applyQueueIntent(
  BuildContext context,
  QueueIntent intent,
  List<Track> tracks,
) {
  if (intent == QueueIntent.play || tracks.isEmpty) return false;
  final audio = context.read<AudioController>();
  if (intent == QueueIntent.addToQueue) {
    final at = audio.addToQueue(tracks);
    showQueueAdditionToast(
      context,
      message: 'Added to end of queue',
      firstPosition: at,
      count: tracks.length,
    );
  } else {
    final at = audio.playNext(tracks);
    showQueueAdditionToast(
      context,
      message: 'Playing next',
      firstPosition: at,
      count: tracks.length,
    );
  }
  return true;
}

/// [applyQueueIntent] for controls whose tracks are already in hand, where the
/// modifiers can be read at the moment of the click.
bool applyQueueModifiers(BuildContext context, List<Track> tracks) =>
    applyQueueIntent(context, readQueueIntent(), tracks);

void showQueueToast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
  );
}

/// Option/Alt-click on a single track: play it now and keep the queue, the
/// interrupted track resuming afterwards. Returns whether it applied, so
/// callers fall through to their own play behaviour otherwise.
bool applyKeepQueueModifier(BuildContext context, Track track) {
  if (!HardwareKeyboard.instance.isAltPressed) return false;
  final playedAt = context.read<AudioController>().playNowKeepingQueue(track);
  showQueueAdditionToast(
    context,
    message: 'Playing now',
    firstPosition: playedAt,
  );
  return true;
}

/// Offers to undo an action the user just took; every undo in the player
/// shares this label and window so they behave the same everywhere.
///
/// Takes the messenger rather than a context: capture it before the action,
/// which often removes the very row that triggered it.
void showUndoToast(
  ScaffoldMessengerState? messenger,
  String message, {
  required VoidCallback onUndo,
}) {
  if (messenger == null) return;
  // Paint the close icon in the action colour so it reads as clearly as
  // Undo on every surface: the M3 default (onInverseSurface) disappears
  // against this app's custom popover background.
  final theme = Theme.of(messenger.context);
  final closeIconColor =
      theme.snackBarTheme.actionTextColor ?? theme.colorScheme.primary;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        // A snack bar with an action otherwise stays until it is used.
        persist: false,
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
        // Snack bars are otherwise only dismissable by swiping, which a mouse
        // user has to discover — an explicit close button is the reliable
        // desktop affordance.
        showCloseIcon: true,
        closeIconColor: closeIconColor,
      ),
    );
}

/// Standard popup for tracks just added to the playback queue. Shows an Undo
/// action that removes the added range again; [firstPosition] and [count] are
/// the insertion point and number of tracks, as returned by
/// [AudioController.addToQueue] or [AudioController.playNext].
void showQueueAdditionToast(
  BuildContext context, {
  required String message,
  required int firstPosition,
  int count = 1,
}) {
  if (firstPosition < 0 || count <= 0) {
    showQueueToast(context, message);
    return;
  }
  final audio = context.read<AudioController>();
  showUndoToast(
    ScaffoldMessenger.maybeOf(context),
    message,
    onUndo: () => unawaited(_undoQueueAddition(audio, firstPosition, count)),
  );
}

Future<void> _undoQueueAddition(
  AudioController audio,
  int firstPosition,
  int count,
) async {
  // Remove tail-first so the positions of the remaining additions stay valid.
  for (var i = count - 1; i >= 0; i--) {
    await audio.removeQueuePosition(firstPosition + i);
  }
}

/// Tooltip suffix documenting the modifiers, appended to the Play buttons that
/// honour them.
String get queueModifierHint => defaultTargetPlatform == TargetPlatform.macOS
    ? '\nShift-click to queue • ⌘-click to play next'
    : '\nShift-click to queue • Ctrl-click to play next';
