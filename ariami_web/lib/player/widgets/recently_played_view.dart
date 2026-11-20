import 'package:ariami_core/models/listening_stats_models.dart'
    show ListeningSongRollup;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/listening_stats_controller.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'context_menu.dart';
import 'queue_intent.dart';

/// Recently played songs derived from qualified Listening Stats rollups.
/// Device handoffs therefore do not manufacture history entries, while plays
/// reported by another Ariami device still appear through the account overlay.
class RecentlyPlayedView extends StatefulWidget {
  const RecentlyPlayedView({super.key});

  @override
  State<RecentlyPlayedView> createState() => _RecentlyPlayedViewState();
}

class _RecentlyPlayedViewState extends State<RecentlyPlayedView> {
  /// Days the user has explicitly opened or closed. Anything untouched
  /// follows [_opensExpanded], so arriving on a years-long history gives a
  /// scannable list of days rather than one endless scroll.
  final Map<String, bool> _collapsedByDay = <String, bool>{};

  /// Deriving the history walks every song rollup a user has ever played, so
  /// on a years-long history it is far too costly to redo on every rebuild —
  /// collapsing a day, a track change, or the minute-rollover stats
  /// notification would each pay for it. The groups are cached and rebuilt
  /// only when one of the two inputs is actually replaced.
  List<ListeningSongRollup>? _sourceStats;
  List<Track>? _sourceTracks;
  List<_DayGroup> _groups = const <_DayGroup>[];

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<ListeningStatsController>().snapshot.songs;
    final tracks = context.watch<LibraryController>().songs;
    if (!identical(stats, _sourceStats) || !identical(tracks, _sourceTracks)) {
      _sourceStats = stats;
      _sourceTracks = tracks;
      _groups = _buildGroups(stats, tracks);
    }
    final groups = _groups;

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _HistoryHeader()),
        if (groups.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyHistory(),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverList.builder(
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final collapsed =
                    _collapsedByDay[group.key] ?? !_opensExpanded(group.day);
                return Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 4 : 14),
                  child: Column(
                    children: [
                      _DayHeader(
                        label: _dayLabel(context, group.day),
                        count: group.entries.length,
                        collapsed: collapsed,
                        onAddToQueue: group.hasPlayableTracks
                            ? () => _addDayToQueue(group)
                            : null,
                        onTap: () => setState(
                          () => _collapsedByDay[group.key] = !collapsed,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: collapsed
                            ? const SizedBox.shrink(key: ValueKey('closed'))
                            : Column(
                                key: ValueKey('open-${group.key}'),
                                children: [
                                  for (final entry in group.entries)
                                    _RecentTrackTile(entry: entry),
                                ],
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _addDayToQueue(_DayGroup group) {
    final tracks = group.entries
        .map((entry) => entry.track)
        .whereType<Track>()
        .toList(growable: false);
    if (tracks.isEmpty) return;
    final at = context.read<AudioController>().addToQueue(tracks);
    final label = tracks.length == 1 ? 'track' : 'tracks';
    showQueueAdditionToast(
      context,
      message: 'Added ${tracks.length} $label to end of queue',
      firstPosition: at,
      count: tracks.length,
    );
  }

  static List<_DayGroup> _buildGroups(
    List<ListeningSongRollup> stats,
    List<Track> tracks,
  ) {
    final library = _LibraryIndex(tracks);
    final played = stats.where((song) => song.lastPlayedMs != null).toList()
      ..sort((a, b) => b.lastPlayedMs!.compareTo(a.lastPlayedMs!));
    final entriesByIdentity = <String, _RecentEntry>{};
    for (final stat in played) {
      final entry = _RecentEntry(
        stat: stat,
        playedAt: DateTime.fromMillisecondsSinceEpoch(stat.lastPlayedMs!),
        track: library.resolve(stat),
      );
      // Stats are already newest-first. Keeping the first matching identity
      // makes a replay move the existing song to the top instead of adding a
      // second row, including after a stale song id is remapped by metadata.
      entriesByIdentity.putIfAbsent(_identityFor(entry), () => entry);
    }
    return _groupByDay(entriesByIdentity.values);
  }

  static String _identityFor(_RecentEntry entry) {
    final track = entry.track;
    if (track != null) return 'track:${track.id}';
    final stat = entry.stat;
    final title = _normalize(stat.songTitle);
    final artist = _normalize(stat.songArtist);
    if (title.isNotEmpty || artist.isNotEmpty) {
      return 'metadata:$title|$artist|${_normalize(stat.album)}';
    }
    return 'stats:${stat.songId}';
  }

  static String _normalize(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static List<_DayGroup> _groupByDay(Iterable<_RecentEntry> entries) {
    final grouped = <String, _DayGroup>{};
    for (final entry in entries) {
      final day = DateTime(
        entry.playedAt.year,
        entry.playedAt.month,
        entry.playedAt.day,
      );
      final key = _dayKey(day);
      final group = grouped.putIfAbsent(
        key,
        () => _DayGroup(key: key, day: day, entries: <_RecentEntry>[]),
      );
      group.entries.add(entry);
      if (entry.track != null) group.hasPlayableTracks = true;
    }
    return grouped.values.toList();
  }

  static String _dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// The last week (today and the six days before it) arrives open; older
  /// days wait to be asked for. Built from calendar day numbers rather than
  /// a subtracted [Duration] so a DST change can't shift the boundary.
  static bool _opensExpanded(DateTime day) {
    final now = DateTime.now();
    return !day.isBefore(DateTime(now.year, now.month, now.day - 6));
  }

  static String _dayLabel(BuildContext context, DateTime value) {
    final now = DateTime.now();
    if (_sameDay(now, value)) return 'TODAY';
    if (_sameDay(now.subtract(const Duration(days: 1)), value)) {
      return 'YESTERDAY';
    }
    final l10n = MaterialLocalizations.of(context);
    final label = l10n.formatMediumDate(value).toUpperCase();
    // A medium date carries no year, so a play from 2019 would read exactly
    // like one from this July. Spell the year out once it isn't this one.
    return value.year == now.year ? label : '$label, ${l10n.formatYear(value)}';
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .secondary
                  .withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history_rounded,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recently played',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  'Add tracks to your queue, or choose Play next from a track’s menu.',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayGroup {
  _DayGroup({
    required this.key,
    required this.day,
    required this.entries,
  });

  final String key;
  final DateTime day;
  final List<_RecentEntry> entries;

  /// Whether any row resolved to a library track, so the day's "add to queue"
  /// action can be enabled without rescanning the entries on every rebuild.
  bool hasPlayableTracks = false;
}

/// Library lookups for history rows, indexed once per library revision.
/// Resolving each rollup by scanning the whole library is O(stats × library)
/// — with an imported history that is millions of string comparisons per
/// rebuild, and most imported plays miss the id lookup entirely.
class _LibraryIndex {
  _LibraryIndex(List<Track> tracks) {
    for (final track in tracks) {
      _byId[track.id] = track;
      _byTitleArtist
          .putIfAbsent(_key(track.title, track.artist), () => <Track>[])
          .add(track);
    }
  }

  final Map<String, Track> _byId = <String, Track>{};
  final Map<String, List<Track>> _byTitleArtist = <String, List<Track>>{};

  Track? resolve(ListeningSongRollup stat) {
    final exact = _byId[stat.songId];
    if (exact != null) return exact;
    final title = stat.songTitle;
    final artist = stat.songArtist;
    if (title == null || artist == null) return null;
    final candidates = _byTitleArtist[_key(title, artist)];
    if (candidates == null) return null;
    if (candidates.length == 1) return candidates.single;
    final album = _RecentlyPlayedViewState._normalize(stat.album);
    final albumArtist = _RecentlyPlayedViewState._normalize(stat.albumArtist);
    final albumMatches = candidates.where((track) {
      final titleMatches = album.isEmpty ||
          _RecentlyPlayedViewState._normalize(track.albumTitle) == album;
      final artistMatches = albumArtist.isEmpty ||
          _RecentlyPlayedViewState._normalize(track.albumArtist) == albumArtist;
      return titleMatches && artistMatches;
    }).toList();
    return albumMatches.length == 1 ? albumMatches.single : null;
  }

  /// The separator keeps "Song A" by "B" from colliding with "Song" by
  /// "A B", which comparing the two fields separately never could.
  static String _key(String title, String artist) =>
      '${title.trim().toLowerCase()}\u0000${artist.trim().toLowerCase()}';
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onAddToQueue,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback? onAddToQueue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: !collapsed,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count ${count == 1 ? 'track' : 'tracks'}',
                  style: TextStyle(
                    color: context.colors.textSecondary.withValues(alpha: 0.65),
                    fontSize: 11.5,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Add this day to end of queue',
                  child: TextButton.icon(
                    onPressed: onAddToQueue,
                    icon: const Icon(Icons.add_to_queue_rounded, size: 17),
                    label: const Text('Add to end of queue'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  collapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  size: 20,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentEntry {
  const _RecentEntry({
    required this.stat,
    required this.playedAt,
    required this.track,
  });

  final ListeningSongRollup stat;
  final DateTime playedAt;
  final Track? track;
}

class _RecentTrackTile extends StatelessWidget {
  const _RecentTrackTile({required this.entry});

  final _RecentEntry entry;

  @override
  Widget build(BuildContext context) {
    final track = entry.track;
    final stat = entry.stat;
    final currentId = context.select<AudioController, String?>(
      (audio) => audio.currentTrack?.id,
    );
    final playing = track != null && currentId == track.id;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(entry.playedAt),
    );
    final title = stat.songTitle ?? track?.title ?? 'Unknown track';
    final artist = stat.songArtist ?? track?.artist ?? 'Unknown artist';

    void openMenu(Offset position) =>
        showTrackContextMenu(context, position, track!);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: playing
            ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTapUp: track == null
              ? null
              : (details) => openMenu(details.globalPosition),
          onSecondaryTapDown: track == null
              ? null
              : (details) => openMenu(details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Artwork(
                  client: context.read<ConnectionController>().client,
                  albumId: track?.albumId ?? stat.albumId,
                  songId: track?.id ?? stat.songId,
                  size: 48,
                  borderRadius: 6,
                  deferDuringScroll: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: playing
                              ? Theme.of(context).colorScheme.secondary
                              : context.colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  time,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: track == null
                      ? 'Unavailable in your library'
                      : 'Add to end of queue',
                  onPressed: track == null
                      ? null
                      : () => applyQueueIntent(
                            context,
                            QueueIntent.addToQueue,
                            [track],
                          ),
                  icon: Icon(track == null
                      ? Icons.music_off_rounded
                      : Icons.playlist_add_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 56,
              color: context.colors.textSecondary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            const Text(
              'Nothing played yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Songs appear here after they count as a play in Listening Stats.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
