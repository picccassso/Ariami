import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../models/song_stats.dart';
import '../../services/api/connection_service.dart';
import '../../services/playback_manager.dart';
import '../../services/stats/account_stats_service.dart';
import '../../services/stats/stats_artwork_resolver.dart';
import '../../services/stats/streaming_stats_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/cached_artwork.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../widgets/common/queue_action_confirmation.dart';

/// Recently played songs derived from qualified Listening Stats rollups.
/// A Connect handoff does not create an entry, while real plays synced from
/// another Ariami device still update the account-wide history.
class RecentlyPlayedScreen extends StatefulWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  State<RecentlyPlayedScreen> createState() => _RecentlyPlayedScreenState();
}

class _RecentlyPlayedScreenState extends State<RecentlyPlayedScreen> {
  final StreamingStatsService _stats = StreamingStatsService();
  final PlaybackManager _playback = PlaybackManager();
  final ConnectionService _connection = ConnectionService();
  final Set<String> _collapsedDays = <String>{};

  Map<String, AlbumModel> _albumsById = const <String, AlbumModel>{};
  List<SongModel> _librarySongs = const <SongModel>[];
  StatsArtworkResolver _artworkResolver = StatsArtworkResolver(
    albums: const <AlbumModel>[],
    songs: const <SongModel>[],
  );
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _stats.initialize();
    if (!mounted) return;
    setState(() => _loading = false);
    unawaited(AccountStatsService().refreshSummary());
    unawaited(_loadLibrary());
  }

  Future<void> _loadLibrary() async {
    try {
      final library = await _connection.libraryReadFacade.getLibraryBundle();
      if (!mounted) return;
      setState(() {
        _albumsById = <String, AlbumModel>{
          for (final album in library.albums) album.id: album,
        };
        _librarySongs = library.songs;
        _artworkResolver = StatsArtworkResolver(
          albums: library.albums,
          songs: library.songs,
        );
      });
    } catch (_) {
      // Listening metadata remains readable while the catalog is unavailable.
    }
  }

  Future<void> _play(_RecentEntry entry) async {
    final song = entry.song;
    if (song == null) return;
    try {
      await _playback.playSingleRepeated(song);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play “${entry.title}”.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recently Played'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ContentWidthLimiter(
        child: ListenableBuilder(
          listenable: _stats,
          builder: (context, _) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }

            final stats = _stats
                .getAllStats()
                .where((stat) => stat.lastPlayed != null)
                .toList()
              ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
            final songsById = <String, SongModel>{
              for (final song in _librarySongs) song.id: song,
            };
            final entriesByIdentity = <String, _RecentEntry>{};
            for (final stat in stats) {
              final entry = _RecentEntry(
                stat: stat,
                song: _resolveSong(stat, _librarySongs, songsById),
              );
              // The list is newest-first, so a repeat updates and repositions
              // this one row. Metadata fallback also collapses stale ids that
              // refer to the same current library song.
              entriesByIdentity.putIfAbsent(
                _identityFor(entry),
                () => entry,
              );
            }
            final entries = entriesByIdentity.values.toList();
            final groups = _groupByDay(entries);
            if (groups.isEmpty) return const _EmptyHistory();

            return MiniPlayerScrollPaddingBuilder(
              builder: (context, bottomPadding) => ListView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 24),
                children: [
                  for (var index = 0; index < groups.length; index++)
                    _buildDaySection(groups[index], index),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDaySection(_DayGroup group, int index) {
    final collapsed = _collapsedDays.contains(group.key);
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
      child: Column(
        children: [
          _DayHeader(
            label: _dayLabel(context, group.day),
            count: group.entries.length,
            collapsed: collapsed,
            onAddToQueue: group.entries.any((entry) => entry.song != null)
                ? () => _addDayToQueue(group)
                : null,
            onTap: () => setState(() {
              if (collapsed) {
                _collapsedDays.remove(group.key);
              } else {
                _collapsedDays.add(group.key);
              }
            }),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: collapsed
                ? const SizedBox.shrink(key: ValueKey('closed'))
                : Column(
                    key: ValueKey('open-${group.key}'),
                    children: [
                      for (final entry in group.entries)
                        _RecentStatsTile(
                          entry: entry,
                          album: entry.albumId == null
                              ? null
                              : _albumsById[entry.albumId],
                          artwork: _artworkResolver.forSong(entry.stat),
                          onTap: entry.song == null ? null : () => _play(entry),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _addDayToQueue(_DayGroup group) {
    final songs = group.entries
        .map((entry) => entry.song)
        .whereType<Song>()
        .toList(growable: false);
    if (songs.isEmpty) return;
    _playback.addAllToQueue(songs);
    final label = songs.length == 1 ? 'track' : 'tracks';
    showQueueActionConfirmation(
      context,
      message: 'Added ${songs.length} $label to queue',
    );
  }

  Song? _resolveSong(
    SongStats stat,
    List<SongModel> librarySongs,
    Map<String, SongModel> songsById,
  ) {
    SongModel? match = songsById[stat.songId];
    final title = stat.songTitle?.trim().toLowerCase();
    final artist = stat.songArtist?.trim().toLowerCase();
    if (match == null && title != null && artist != null) {
      final candidates = librarySongs
          .where((candidate) =>
              candidate.title.trim().toLowerCase() == title &&
              candidate.artist.trim().toLowerCase() == artist)
          .toList();
      if (candidates.length == 1) {
        match = candidates.single;
      } else if (candidates.length > 1) {
        final albumTitle = _normalize(stat.album);
        final albumArtist = _normalize(stat.albumArtist);
        final albumMatches = candidates.where((candidate) {
          final album =
              candidate.albumId == null ? null : _albumsById[candidate.albumId];
          final titleMatches =
              albumTitle.isEmpty || _normalize(album?.title) == albumTitle;
          final artistMatches =
              albumArtist.isEmpty || _normalize(album?.artist) == albumArtist;
          return titleMatches && artistMatches;
        }).toList();
        if (albumMatches.length == 1) match = albumMatches.single;
      }
    }
    if (match == null) return null;
    final album = match.albumId == null ? null : _albumsById[match.albumId];
    return Song(
      id: match.id,
      title: match.title,
      artist: match.artist,
      album: album?.title ?? stat.album,
      albumId: match.albumId ?? stat.albumId,
      albumArtist: album?.artist ?? stat.albumArtist,
      duration: Duration(seconds: match.duration),
      trackNumber: match.trackNumber,
      filePath: match.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
    );
  }

  static String _identityFor(_RecentEntry entry) {
    final song = entry.song;
    if (song != null) return 'song:${song.id}';
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

  static List<_DayGroup> _groupByDay(List<_RecentEntry> entries) {
    final grouped = <String, _DayGroup>{};
    for (final entry in entries) {
      final playedAt = entry.stat.lastPlayed!;
      final day = DateTime(playedAt.year, playedAt.month, playedAt.day);
      final key = _dayKey(day);
      grouped
          .putIfAbsent(
            key,
            () => _DayGroup(key: key, day: day, entries: <_RecentEntry>[]),
          )
          .entries
          .add(entry);
    }
    return grouped.values.toList();
  }

  static String _dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(BuildContext context, DateTime value) {
    final now = DateTime.now();
    if (_sameDay(now, value)) return 'TODAY';
    if (_sameDay(now.subtract(const Duration(days: 1)), value)) {
      return 'YESTERDAY';
    }
    return MaterialLocalizations.of(context)
        .formatMediumDate(value)
        .toUpperCase();
  }
}

class _RecentEntry {
  const _RecentEntry({required this.stat, required this.song});

  final SongStats stat;
  final Song? song;

  String get title => stat.songTitle ?? song?.title ?? 'Unknown track';
  String get artist => stat.songArtist ?? song?.artist ?? 'Unknown artist';
  String? get albumId => stat.albumId ?? song?.albumId;
  String? get album => stat.album ?? song?.album;
}

class _DayGroup {
  const _DayGroup({
    required this.key,
    required this.day,
    required this.entries,
  });

  final String key;
  final DateTime day;
  final List<_RecentEntry> entries;
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
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      expanded: !collapsed,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count ${count == 1 ? 'track' : 'tracks'}',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Add this day to queue',
                  child: TextButton.icon(
                    onPressed: onAddToQueue,
                    icon: const Icon(Icons.add_to_queue_rounded, size: 17),
                    label: const Text('Add to queue'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Icon(
                  collapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentStatsTile extends StatelessWidget {
  const _RecentStatsTile({
    required this.entry,
    required this.album,
    required this.artwork,
    required this.onTap,
  });

  final _RecentEntry entry;
  final AlbumModel? album;
  final StatsArtworkIdentity artwork;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playedAt = entry.stat.lastPlayed!;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(playedAt),
    );
    final albumLabel = entry.album ?? album?.title;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CachedArtwork(
                albumId: artwork.cacheId,
                artworkUrl: artwork.artworkUrl,
                width: 54,
                height: 54,
                borderRadius: BorderRadius.circular(12),
                sizeHint: ArtworkSizeHint.thumbnail,
                fallbackIconSize: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      albumLabel == null
                          ? entry.artist
                          : '${entry.artist} • $albumLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      time,
                      style: TextStyle(
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                onTap == null
                    ? Icons.music_off_rounded
                    : Icons.play_circle_fill_rounded,
                color: onTap == null
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
                    : colorScheme.primary,
                size: 30,
              ),
            ],
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
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_toggle_off_rounded,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nothing played yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Songs appear here after they count as a play in Listening Stats.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
