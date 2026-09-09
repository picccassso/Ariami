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
import '../../widgets/common/song_overflow_menu.dart';
import '../album_detail_screen.dart';
import '../playlist/add_to_playlist_screen.dart';

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

  /// Days the user has explicitly opened or closed. Anything untouched
  /// follows [_opensExpanded], so arriving on a years-long history gives a
  /// scannable list of days rather than one endless scroll.
  final Map<String, bool> _collapsedByDay = <String, bool>{};

  Map<String, AlbumModel> _albumsById = const <String, AlbumModel>{};
  List<SongModel> _librarySongs = const <SongModel>[];
  StatsArtworkResolver _artworkResolver = StatsArtworkResolver(
    albums: const <AlbumModel>[],
    songs: const <SongModel>[],
  );

  /// Deriving the history walks every rollup the account has ever recorded
  /// and resolves each one against the library, so it is rebuilt only when
  /// the stats or the catalog actually change — never on a collapse toggle.
  List<_DayGroup> _groups = const <_DayGroup>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _stats.addListener(_onStatsChanged);
    _initialize();
  }

  @override
  void dispose() {
    _stats.removeListener(_onStatsChanged);
    super.dispose();
  }

  void _onStatsChanged() {
    if (!mounted) return;
    setState(_rebuildGroups);
  }

  Future<void> _initialize() async {
    await _stats.initialize();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rebuildGroups();
    });
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
        _rebuildGroups();
      });
    } catch (_) {
      // Listening metadata remains readable while the catalog is unavailable.
    }
  }

  void _rebuildGroups() {
    final stats = _stats
        .getAllStats()
        .where((s) => s.lastPlayed != null)
        .toList()
      ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
    final library = _LibraryIndex(_librarySongs, _albumsById);
    final entriesByIdentity = <String, _RecentEntry>{};
    for (final stat in stats) {
      final entry = _RecentEntry(stat: stat, song: library.resolve(stat));
      // The list is newest-first, so a repeat updates and repositions
      // this one row. Metadata fallback also collapses stale ids that
      // refer to the same current library song.
      entriesByIdentity.putIfAbsent(_identityFor(entry), () => entry);
    }
    _groups = _groupByDay(entriesByIdentity.values);
  }

  Future<void> _playSong(_RecentEntry entry) async {
    final song = entry.song;
    if (song == null) return;
    try {
      await _playback.playSong(song);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play “${entry.title}”.')),
      );
    }
  }

  void _queueSong(_RecentEntry entry, {bool next = false}) {
    final song = entry.song;
    if (song == null) return;
    if (!mounted) return;
    if (next) {
      _playback.playNext(song);
    } else {
      _playback.addToQueue(song);
    }
    showQueueActionConfirmation(
      context,
      message: next ? 'Playing next' : 'Added to queue',
    );
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
        child: Builder(
          builder: (context) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_groups.isEmpty) return const _EmptyHistory();

            return MiniPlayerScrollPaddingBuilder(
              builder: (context, bottomPadding) => ListView.builder(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 24),
                itemCount: _groups.length + 1,
                itemBuilder: (context, index) => index == 0
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Tap a track for options. Use + to add it to the end.',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : _buildDaySection(_groups[index - 1], index - 1),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDaySection(_DayGroup group, int index) {
    final collapsed = _collapsedByDay[group.key] ?? !_opensExpanded(group.day);
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
      child: Column(
        children: [
          _DayHeader(
            label: _dayLabel(context, group.day),
            count: group.entries.length,
            collapsed: collapsed,
            onAddToQueue:
                group.hasPlayableSongs ? () => _addDayToQueue(group) : null,
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
                        _RecentStatsTile(
                          entry: entry,
                          album: entry.albumId == null
                              ? null
                              : _albumsById[entry.albumId],
                          artwork: _artworkResolver.forSong(entry.stat),
                          onPlay: entry.song == null
                              ? null
                              : () => _playSong(entry),
                          onAddToQueue: entry.song == null
                              ? null
                              : () => _queueSong(entry),
                          onPlayNext: entry.song == null
                              ? null
                              : () => _queueSong(entry, next: true),
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

  static List<_DayGroup> _groupByDay(Iterable<_RecentEntry> entries) {
    final grouped = <String, _DayGroup>{};
    for (final entry in entries) {
      final playedAt = entry.stat.lastPlayed!;
      final day = DateTime(playedAt.year, playedAt.month, playedAt.day);
      final key = _dayKey(day);
      final group = grouped.putIfAbsent(
        key,
        () => _DayGroup(key: key, day: day, entries: <_RecentEntry>[]),
      );
      group.entries.add(entry);
      if (entry.song != null) group.hasPlayableSongs = true;
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

class _RecentEntry {
  const _RecentEntry({required this.stat, required this.song});

  final SongStats stat;
  final Song? song;

  String get title {
    final statTitle = stat.songTitle?.trim();
    if (statTitle != null && statTitle.isNotEmpty) return statTitle;
    final songTitle = song?.title.trim();
    if (songTitle != null && songTitle.isNotEmpty) return songTitle;
    return 'Unknown track';
  }

  String get artist {
    final statArtist = stat.songArtist?.trim();
    if (statArtist != null && statArtist.isNotEmpty) return statArtist;
    final songArtist = song?.artist.trim();
    if (songArtist != null && songArtist.isNotEmpty) return songArtist;
    return 'Unknown artist';
  }

  String? get albumId {
    final statId = stat.albumId?.trim();
    if (statId != null && statId.isNotEmpty) return statId;
    final songId = song?.albumId?.trim();
    if (songId != null && songId.isNotEmpty) return songId;
    return null;
  }

  String? get album {
    final statAlbum = stat.album?.trim();
    if (statAlbum != null && statAlbum.isNotEmpty) return statAlbum;
    final songAlbum = song?.album?.trim();
    if (songAlbum != null && songAlbum.isNotEmpty) return songAlbum;
    return null;
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

  /// Whether any row resolved to a library song, so the day's "add to queue"
  /// action can be enabled without rescanning the entries on every rebuild.
  bool hasPlayableSongs = false;
}

/// Library lookups for history rows, indexed once per catalog load.
/// Resolving each rollup by scanning the whole library is O(stats × library)
/// — with an imported history that is millions of string comparisons, and
/// every play the importer could not match misses the id lookup entirely.
class _LibraryIndex {
  _LibraryIndex(List<SongModel> songs, this._albumsById) {
    for (final song in songs) {
      _byId[song.id] = song;
      _byTitleArtist
          .putIfAbsent(_key(song.title, song.artist), () => <SongModel>[])
          .add(song);
    }
  }

  final Map<String, AlbumModel> _albumsById;
  final Map<String, SongModel> _byId = <String, SongModel>{};
  final Map<String, List<SongModel>> _byTitleArtist =
      <String, List<SongModel>>{};

  Song? resolve(SongStats stat) {
    final match = _byId[stat.songId] ?? _byMetadata(stat);
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

  SongModel? _byMetadata(SongStats stat) {
    final title = stat.songTitle;
    final artist = stat.songArtist;
    if (title == null || artist == null) return null;
    final candidates = _byTitleArtist[_key(title, artist)];
    if (candidates == null) return null;
    if (candidates.length == 1) return candidates.single;
    final albumTitle = _RecentlyPlayedScreenState._normalize(stat.album);
    final albumArtist = _RecentlyPlayedScreenState._normalize(stat.albumArtist);
    final albumMatches = candidates.where((candidate) {
      final album =
          candidate.albumId == null ? null : _albumsById[candidate.albumId];
      final titleMatches = albumTitle.isEmpty ||
          _RecentlyPlayedScreenState._normalize(album?.title) == albumTitle;
      final artistMatches = albumArtist.isEmpty ||
          _RecentlyPlayedScreenState._normalize(album?.artist) == albumArtist;
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
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
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
                      Text(
                        '$count ${count == 1 ? 'track' : 'tracks'}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.65),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
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
    required this.onPlay,
    required this.onAddToQueue,
    required this.onPlayNext,
  });

  final _RecentEntry entry;
  final AlbumModel? album;
  final StatsArtworkIdentity artwork;
  final VoidCallback? onPlay;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onPlayNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playedAt = entry.stat.lastPlayed!;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(playedAt),
    );
    final albumLabel = entry.album ?? album?.title;
    final hasAlbumLabel = albumLabel != null && albumLabel.trim().isNotEmpty;
    final isAvailable = entry.song != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isAvailable ? () => _showSongActions(context) : null,
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
                      hasAlbumLabel
                          ? '${entry.artist} • $albumLabel'
                          : entry.artist,
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
              IconButton(
                tooltip: onAddToQueue == null
                    ? 'Unavailable in your library'
                    : 'Add to queue',
                onPressed: onAddToQueue,
                icon: Icon(onAddToQueue == null
                    ? Icons.music_off_rounded
                    : Icons.playlist_add_rounded),
                color: colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSongActions(BuildContext context) {
    final song = entry.song;
    if (song == null) return;

    final resolvedAlbumId = entry.albumId;
    final songModel = SongModel(
      id: song.id,
      title: entry.title,
      artist: entry.artist,
      genre: song.genre,
      albumId: resolvedAlbumId,
      duration: song.duration.inSeconds,
      trackNumber: song.trackNumber,
    );

    showAriamiSheet<void>(
      context: context,
      header: AriamiSheetHeader(
        title: entry.title,
        subtitle: entry.artist,
        leading: const Icon(Icons.music_note_rounded, size: 28),
      ),
      items: [
        ListTile(
          leading: const Icon(Icons.play_arrow),
          title: const Text('Play'),
          onTap: () {
            Navigator.pop(context);
            onPlay?.call();
          },
        ),
        SongLikeMenuItem(song: songModel),
        ListTile(
          leading: const Icon(Icons.skip_next),
          title: const Text('Play Next'),
          onTap: () {
            Navigator.pop(context);
            onPlayNext?.call();
          },
        ),
        ListTile(
          leading: const Icon(Icons.queue_music),
          title: const Text('Add to Queue'),
          onTap: () {
            Navigator.pop(context);
            onAddToQueue?.call();
          },
        ),
        ListTile(
          leading: const Icon(Icons.playlist_add),
          title: const Text('Add to Playlist'),
          onTap: () {
            Navigator.pop(context);
            if (!context.mounted) return;
            AddToPlaylistScreen.showForSong(
              context,
              song.id,
              albumId: resolvedAlbumId,
              title: entry.title,
              artist: entry.artist,
              duration: song.duration.inSeconds,
            );
          },
        ),
        if (resolvedAlbumId != null && resolvedAlbumId.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.album_outlined),
            title: const Text('Show in album'),
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              if (!context.mounted) return;
              final albumArtist =
                  (song.albumArtist?.trim().isNotEmpty == true)
                      ? song.albumArtist!.trim()
                      : entry.artist;
              final albumModel = album ??
                  AlbumModel(
                    id: resolvedAlbumId,
                    title: entry.album ?? 'Unknown Album',
                    artist: albumArtist,
                    songCount: 0,
                    duration: 0,
                  );
              nav.push(
                MaterialPageRoute(
                  builder: (context) => AlbumDetailScreen(album: albumModel),
                ),
              );
            },
          ),
      ],
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
