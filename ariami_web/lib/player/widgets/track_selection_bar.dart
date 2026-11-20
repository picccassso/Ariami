import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/player_host.dart';
import '../theme/player_theme.dart';
import 'context_menu.dart';
import 'playback_helpers.dart';
import 'playlists_menu.dart';
import 'queue_intent.dart';

/// Floating action bar for a multi-selection, mirroring mobile's batch bar:
/// the same verbs a single track's right-click menu offers, applied to the
/// whole selection in one go.
///
/// Every action finishes by dismissing the selection — the batch is done, and
/// leaving the bar up invites a second accidental Download on the same songs.
class TrackSelectionBar extends StatelessWidget {
  const TrackSelectionBar({
    super.key,
    required this.selected,
    required this.onSelectAll,
    required this.onDone,
  });

  final List<Track> selected;
  final VoidCallback onSelectAll;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final count = selected.length;
    final enabled = count > 0;
    // Downloads only exist when playing from a remote server — when this
    // computer hosts the library, the files are already on its disk. Same
    // rule the track/collection menus and the downloads settings follow.
    final canDownload =
        !context.select<ConnectionController, bool>((c) => c.isLocalServer) &&
            (maybeReadProvider<PlayerDownloadsBridge?>(context) ??
                    maybeReadProvider<PlayerDownloadsBridge>(context)) !=
                null;
    return LayoutBuilder(
      builder: (context, constraints) => _bar(
        context,
        count: count,
        enabled: enabled,
        canDownload: canDownload,
        // Below this the two text buttons are what tips the bar into
        // overflow, so they become icons and everything still fits.
        compact: constraints.maxWidth < 560,
      ),
    );
  }

  Widget _bar(
    BuildContext context, {
    required int count,
    required bool enabled,
    required bool canDownload,
    required bool compact,
  }) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          color: context.colors.popover,
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count == 0 ? 'Select songs' : '$count selected',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                if (compact)
                  SelectionBarAction(
                    icon: Icons.select_all_rounded,
                    label: 'Select all',
                    onPressed: onSelectAll,
                  )
                else
                  TextButton(
                    onPressed: onSelectAll,
                    child: const Text('Select all'),
                  ),
                const SelectionBarDivider(),
                SelectionBarAction(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play now',
                  // No sourceId: an ad-hoc selection isn't a collection, so
                  // nothing in the UI should light up as "now playing from".
                  onPressed: enabled
                      ? () {
                          context.read<AudioController>().playAll(selected);
                          onDone();
                        }
                      : null,
                ),
                SelectionBarAction(
                  icon: Icons.queue_music_rounded,
                  label: 'Add to end of queue',
                  onPressed: enabled
                      ? () {
                          final at =
                              context.read<AudioController>().addToQueue(selected);
                          showQueueAdditionToast(
                            context,
                            message: '${_songs(count)} added to end of queue',
                            firstPosition: at,
                            count: count,
                          );
                          onDone();
                        }
                      : null,
                ),
                SelectionBarAction(
                  icon: Icons.playlist_add_rounded,
                  label: 'Playlists…',
                  // The picker is a popup menu, so it needs an anchor point;
                  // the bar's own position puts it right above the buttons.
                  onPressed: enabled
                      ? () async {
                          final changed = await showPlaylistsMenu(
                            context,
                            menuAnchorOf(context),
                            selected,
                          );
                          // A dismissed picker changed nothing, so the selection
                          // is still wanted.
                          if (changed) onDone();
                        }
                      : null,
                ),
                if (canDownload)
                  SelectionBarAction(
                    icon: Icons.download_rounded,
                    label: 'Download',
                    onPressed: enabled
                        ? () async {
                            await enqueueTrackDownloads(context, selected);
                            onDone();
                          }
                        : null,
                  ),
                const SelectionBarDivider(),
                if (compact)
                  SelectionBarAction(
                    icon: Icons.done_rounded,
                    label: 'Done',
                    onPressed: onDone,
                  )
                else
                  TextButton(onPressed: onDone, child: const Text('Done')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _songs(int n) => n == 1 ? '1 song' : '$n songs';

/// Turns multi-select on and off. The discoverable way in — cmd/shift-click
/// on a row does the same thing without it. Styled as a quiet outlined control
/// so it reads as a mode switch, not another play action.
class SelectModeButton extends StatelessWidget {
  const SelectModeButton({
    super.key,
    required this.selecting,
    required this.onPressed,
  });

  final bool selecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(
          selecting ? Icons.close_rounded : Icons.playlist_add_check_rounded,
          size: 18,
        ),
        label: Text(selecting ? 'Cancel' : 'Select'),
        style: OutlinedButton.styleFrom(
          foregroundColor: selecting ? accent : context.colors.textSecondary,
          side: BorderSide(color: selecting ? accent : context.colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }
}

/// The same switch as [SelectModeButton] in the icon-button idiom the detail
/// views' action rows use — where a labelled pill both looked out of place and
/// pushed those rows into overflow on a narrow window.
class SelectModeIconButton extends StatelessWidget {
  const SelectModeIconButton({
    super.key,
    required this.selecting,
    required this.onPressed,
  });

  final bool selecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: selecting ? 'Cancel selection' : 'Select songs',
      icon: Icon(
        selecting ? Icons.close_rounded : Icons.playlist_add_check_rounded,
        size: 26,
      ),
      color: selecting
          ? Theme.of(context).colorScheme.secondary
          : context.colors.textSecondary,
      onPressed: onPressed,
    );
  }
}

/// Icon-only with a tooltip: four labelled buttons plus the count and the
/// two text actions overflowed the bar on any window narrow enough to matter,
/// and a floating bar reads better compact anyway.
class SelectionBarAction extends StatelessWidget {
  const SelectionBarAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      color: context.colors.textPrimary,
      disabledColor: context.colors.textSecondary,
      visualDensity: VisualDensity.compact,
    );
  }
}

class SelectionBarDivider extends StatelessWidget {
  const SelectionBarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        height: 22,
        child: VerticalDivider(width: 1, color: context.colors.border),
      ),
    );
  }
}
