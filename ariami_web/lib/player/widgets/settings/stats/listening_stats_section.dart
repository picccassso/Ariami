import 'dart:async';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/stats_range.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ariami_core/utils/format.dart';

import '../../../models/player_models.dart';
import '../../../services/connection_controller.dart';
import '../../../services/library_controller.dart';
import '../../../services/listening_stats_controller.dart';
import '../../../services/player_host.dart';
import '../../../services/spotify_import_controller.dart';
import '../../../utils/date_formatter.dart';
import '../../../theme/player_theme.dart';
import 'playtime_format.dart';
import 'spotify_import/spotify_import_dialog.dart';
import 'stats_models.dart';
import 'widgets/stats_list_items.dart';
import 'widgets/stats_overview.dart';
import 'widgets/stats_period_selector.dart';
import 'widgets/stats_share_card.dart';
import 'widgets/stats_share_dialog.dart';

class ListeningStatsSection extends StatefulWidget {
  const ListeningStatsSection({super.key});

  @override
  State<ListeningStatsSection> createState() => _ListeningStatsSectionState();
}

class _ListeningStatsSectionState extends State<ListeningStatsSection> {
  StatsCategory _category = StatsCategory.tracks;

  /// Shared range model (ariami_core), so desktop and mobile agree on what
  /// "week"/"month" mean and page through history identically.
  StatsRange _range = StatsRange.specificDay(DateTime.now());
  ListeningPeriodStats? _periodStats;
  bool _loadingPeriod = false;
  bool _periodUnavailable = false;
  int _periodRequestSeq = 0;
  bool _resetting = false;
  bool _removingSpotifyImport = false;

  /// Session-lived stats per exact day range, shown immediately when the user
  /// revisits a range while the fresh fetch replaces them in the background.
  final Map<String, ListeningPeriodStats> _periodMemo =
      <String, ListeningPeriodStats>{};

  /// Shaping period stats into a snapshot re-matches credited artists, so it
  /// must run once per fetched period, not once per widget build.
  ListeningPeriodStats? _periodSnapshotFor;
  ListeningStatsSnapshot? _periodSnapshotCache;

  /// PLAYTIME (and AVG DAILY) cycle through hours, minutes, and compact
  /// minutes when the PLAYTIME metric is clicked. Until the very first click
  /// a little mouse cursor demonstrates the gesture on the metric, and that
  /// first click triggers a one-time explainer dialog.
  static const String _playtimeHintSeenKey = 'stats_playtime_hint_seen';
  static const String _playtimeUnitKey = 'stats_playtime_unit';
  PlaytimeUnit _playtimeUnit = PlaytimeUnit.hours;
  bool _playtimeHintPending = false;

  /// PLAYTIME total (ms) for the currently shown view, captured in [build] so
  /// the tap handler can skip compact minutes when it wouldn't differ from
  /// plain minutes (i.e. under 1000 minutes).
  int _playtimeTotalMs = 0;

  @override
  void initState() {
    super.initState();
    unawaited(SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      final index = prefs.getInt(_playtimeUnitKey) ?? 0;
      final unit =
          PlaytimeUnit.values[index.clamp(0, PlaytimeUnit.values.length - 1)];
      final hintPending = !(prefs.getBool(_playtimeHintSeenKey) ?? false);
      if (unit == PlaytimeUnit.hours && !hintPending) return;
      setState(() {
        _playtimeUnit = unit;
        _playtimeHintPending = hintPending;
      });
    }));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
            context.read<ListeningStatsController>().refreshAccountStats());
        unawaited(_loadPeriod());
      }
    });
  }

  /// The next unit in the cycle, skipping compact minutes when it would render
  /// identically to plain minutes (under 1000 minutes) so the user never taps
  /// through a no-op change on the way back to hours.
  PlaytimeUnit _nextPlaytimeUnit(PlaytimeUnit current) {
    var next =
        PlaytimeUnit.values[(current.index + 1) % PlaytimeUnit.values.length];
    if (next == PlaytimeUnit.minutesCompact &&
        Duration(milliseconds: _playtimeTotalMs).inMinutes < 1000) {
      next = PlaytimeUnit.hours;
    }
    return next;
  }

  void _onPlaytimeTap() {
    final firstTap = _playtimeHintPending;
    setState(() {
      _playtimeUnit = _nextPlaytimeUnit(_playtimeUnit);
      _playtimeHintPending = false;
    });
    final unitIndex = _playtimeUnit.index;
    unawaited(SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_playtimeUnitKey, unitIndex);
      if (firstTap) prefs.setBool(_playtimeHintSeenKey, true);
    }));
    if (!firstTap) return;
    _showPlaytimeHintDialog();
  }

  /// One-time explainer shown right after the first PLAYTIME click, so the
  /// value switching units doesn't read as a glitch.
  void _showPlaytimeHintDialog() {
    unawaited(showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Playtime units'),
        content: const Text(
          'Clicking PLAYTIME cycles it — and AVG DAILY — through hours, '
          'minutes, and compact minutes. Keep clicking to move through them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    ));
  }

  void _selectRange(StatsRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _periodStats = null;
      _periodUnavailable = false;
    });
    if (!range.isAllTime) unawaited(_loadPeriod());
  }

  /// Switches granularity from the selector bar. Re-tapping Day opens the
  /// date picker; everything else jumps to the current calendar unit.
  void _selectGranularity(StatsRangeKind kind) {
    final now = DateTime.now();
    switch (kind) {
      case StatsRangeKind.all:
        _selectRange(StatsRange.all);
      case StatsRangeKind.today:
      case StatsRangeKind.day:
        if (_range.isSingleDay) {
          unawaited(_pickSpecificDay());
        } else {
          _selectRange(StatsRange.specificDay(now));
        }
      case StatsRangeKind.week:
        _selectRange(StatsRange.weekOf(now));
      case StatsRangeKind.month:
        _selectRange(StatsRange.monthOf(now));
      case StatsRangeKind.year:
        _selectRange(StatsRange.yearOf(now));
    }
  }

  void _step(int delta) {
    if (!_range.isSteppable) return;
    if (delta > 0 && !_range.canStepForward()) return;
    if (delta < 0 && !_range.canStepBack(_earliestDay())) return;
    _selectRange(_range.stepped(delta));
  }

  /// The account's first listening day (`yyyy-mm-dd`), used to block paging
  /// back past the start of history. Null with no listening at all.
  String? _earliestDay() {
    int? earliestMs;
    final snapshot = context.read<ListeningStatsController>().snapshot;
    for (final song in snapshot.songs) {
      final first = song.firstPlayedMs;
      if (first != null && (earliestMs == null || first < earliestMs)) {
        earliestMs = first;
      }
    }
    if (earliestMs == null) return null;
    return StatsRange.formatLocalDay(
        DateTime.fromMillisecondsSinceEpoch(earliestMs));
  }

  Future<void> _pickSpecificDay() async {
    final now = DateTime.now();
    // Block picking days outside the account's listening history.
    final earliest = _earliestDay();
    final firstDate =
        earliest != null ? DateTime.parse(earliest) : DateTime(2000);
    var initial = _range.day ?? now;
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(now)) initial = now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    _selectRange(StatsRange.specificDay(picked));
  }

  Future<void> _loadPeriod() async {
    final bounds = _range.bounds();
    if (bounds == null) return;
    final seq = ++_periodRequestSeq;
    final memoKey = '${bounds.from}|${bounds.to}';
    final memoized = _periodMemo[memoKey];
    setState(() {
      _loadingPeriod = true;
      _periodUnavailable = false;
      // Stale-while-revalidate: a previously seen range renders instantly
      // while the fresh fetch replaces it below.
      if (memoized != null) _periodStats = memoized;
    });
    final stats =
        await context.read<ListeningStatsController>().loadPeriodStats(
              fromDay: bounds.from,
              toDay: bounds.to,
            );
    if (!mounted || seq != _periodRequestSeq) return;
    setState(() {
      _loadingPeriod = false;
      if (stats != null) _periodMemo[memoKey] = stats;
      _periodStats = stats ?? memoized;
      _periodUnavailable = stats == null && memoized == null;
    });
  }

  ListeningStatsSnapshot _periodSnapshotCached(ListeningPeriodStats period) {
    if (!identical(_periodSnapshotFor, period)) {
      _periodSnapshotFor = period;
      _periodSnapshotCache = _periodSnapshot(period);
    }
    return _periodSnapshotCache!;
  }

  /// Shapes server period stats like the all-time snapshot so the overview
  /// and rank rows render identically for both.
  ListeningStatsSnapshot _periodSnapshot(ListeningPeriodStats period) {
    var calendarDays = period.days.values
        .where((total) => total.listenedMs > 0 || total.playCount > 0)
        .length;
    final from = DateTime.tryParse(period.fromDay);
    final to = DateTime.tryParse(period.toDay);
    if (from != null && to != null) {
      calendarDays = to.difference(from).inDays + 1;
    }
    final albumCatalog = <String, Album>{
      for (final album in context.read<LibraryController>().albums)
        album.id: album,
    };
    return ListeningStatsSnapshot(
      songs: period.songs,
      artists: creditedArtistStats(period.artists, period.songs),
      albums: serverAlbumStats(
        period.albums,
        albumCatalog: albumCatalog,
      ),
      totalListenedMs: period.totalListenedMs,
      totalPlays: period.totalPlays,
      averageDailyMs:
          calendarDays > 0 ? period.totalListenedMs ~/ calendarDays : 0,
    );
  }

  /// Baseline imports preserve their all-time totals but cannot be split into
  /// precise days. If the selected year contains every recorded first/last
  /// timestamp, the all-time snapshot is therefore also the exact year
  /// snapshot and avoids dropping that imported history.
  bool _yearCoversAllHistory(ListeningStatsSnapshot snapshot) {
    if (_range.kind != StatsRangeKind.year || snapshot.songs.isEmpty) {
      return false;
    }
    int? firstPlayedMs;
    int? lastPlayedMs;
    for (final song in snapshot.songs) {
      final first = song.firstPlayedMs;
      final last = song.lastPlayedMs;
      if (first == null || last == null) return false;
      if (firstPlayedMs == null || first < firstPlayedMs) {
        firstPlayedMs = first;
      }
      if (lastPlayedMs == null || last > lastPlayedMs) {
        lastPlayedMs = last;
      }
    }
    return _range.coversHistory(
      firstPlayed: DateTime.fromMillisecondsSinceEpoch(firstPlayedMs!),
      lastPlayed: DateTime.fromMillisecondsSinceEpoch(lastPlayedMs!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ListeningStatsController>();
    final connection = context.watch<ConnectionController>();
    final useAllTime =
        _range.isAllTime || _yearCoversAllHistory(controller.snapshot);
    final period = _periodStats;
    final stats = useAllTime
        ? controller.snapshot
        : (period == null
            ? ListeningStatsSnapshot.empty
            : _periodSnapshotCached(period));
    _playtimeTotalMs = stats.totalListenedMs;
    final rows = _rowsFor(stats).toList();

    // The persistent undo is offered only while a connected, capable
    // server with an error-free stats view actually reports a Spotify
    // import in this run's live fetch.
    final canRemoveSpotifyImport = connection.client != null &&
        connection.serverInfo?.supportsListeningSourceReset == true &&
        controller.hasSpotifyImport &&
        controller.accountStatsError == null;

    return Stack(
      children: [
        _buildContent(controller, useAllTime, period, stats, rows,
            canRemoveSpotifyImport),

        // Floating period selector pinned at the bottom of the section:
        // ‹ period › stepper plus a granularity row (matches mobile).
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: StatsPeriodSelector(
              range: _range,
              canStepBack:
                  _range.isSteppable && _range.canStepBack(_earliestDay()),
              canStepForward: _range.isSteppable && _range.canStepForward(),
              onStep: _step,
              onSelectGranularity: _selectGranularity,
              onPickDay: () => unawaited(_pickSpecificDay()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    ListeningStatsController controller,
    bool isAllTime,
    ListeningPeriodStats? period,
    ListeningStatsSnapshot stats,
    List<ListeningRankItem> rows,
    bool canRemoveSpotifyImport,
  ) {
    // The rank rows render as a lazy sliver list so only the visible tiles
    // are ever built; the card look survives by splitting it into a header,
    // per-row segments, and a rounded footer sharing the same background.
    final Widget? statusMessage;
    if (!isAllTime && _loadingPeriod && period == null) {
      statusMessage = const StatsMessage(
        icon: Icons.hourglass_top_rounded,
        message: 'Loading stats for this period…',
      );
    } else if (!isAllTime && _periodUnavailable) {
      statusMessage = const StatsMessage(
        icon: Icons.cloud_off_rounded,
        message: 'Stats for this period need a connection to your server '
            '(and a server that supports period stats).',
      );
    } else if (rows.isEmpty) {
      statusMessage = StatsMessage(
        icon: Icons.music_note_rounded,
        message: !isAllTime
            ? 'No listening in this period yet.'
            : controller.isRefreshingAccountStats && !controller.hasAccountStats
                ? 'Loading your listening history…'
                : 'No stats yet. Start listening to see your top ${_category.name}.',
      );
    } else {
      statusMessage = null;
    }

    final canShare = (isAllTime || (period != null && !_periodUnavailable)) &&
        (stats.songs.isNotEmpty ||
            stats.artists.isNotEmpty ||
            stats.albums.isNotEmpty);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
            child: Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.colors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Listening Stats',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your account-wide listening across every Ariami device.',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        if (controller.spotifyImportStatus?.hasImport ??
                            false) ...[
                          const SizedBox(height: 6),
                          Text(
                            _spotifyImportLine(controller.spotifyImportStatus!),
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (controller.isRefreshingAccountStats)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      onPressed: () {
                        unawaited(controller.refreshAccountStats());
                        if (!isAllTime) unawaited(_loadPeriod());
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'Refresh listening stats',
                    ),
                  IconButton(
                    onPressed: canShare ? () => _openShareDialog(stats) : null,
                    icon: const Icon(Icons.share_rounded, size: 20),
                    tooltip: 'Export stats image',
                  ),
                  IconButton(
                    onPressed: _openSpotifyImport,
                    icon: const Icon(Icons.file_upload_outlined, size: 20),
                    tooltip: 'Import from Spotify',
                  ),
                  if (canRemoveSpotifyImport)
                    IconButton(
                      key: const ValueKey('remove_spotify_import_button'),
                      onPressed: _removingSpotifyImport ||
                              controller.isRefreshingAccountStats
                          ? null
                          : _confirmRemoveSpotifyImport,
                      icon: Icon(
                        Icons.undo_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      tooltip: 'Remove Spotify import',
                    ),
                  IconButton(
                    onPressed: _resetting || controller.isRefreshingAccountStats
                        ? null
                        : _confirmReset,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    tooltip: 'Reset listening stats',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              StatsOverview(
                category: _category,
                stats: stats,
                unit: _playtimeUnit,
                pulsePlaytime: _playtimeHintPending,
                onPlaytimeTap: _onPlaytimeTap,
              ),
              if (controller.accountStatsError != null) ...[
                const SizedBox(height: 16),
                StatsMessage(
                  icon: Icons.cloud_off_rounded,
                  message: controller.accountStatsError!,
                ),
              ],
            ],
          ),
        )),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(
            child: Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.colors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in StatsCategory.values)
                    StatsTab(
                      label: switch (category) {
                        StatsCategory.tracks => 'Tracks',
                        StatsCategory.artists => 'Artists',
                        StatsCategory.albums => 'Albums',
                      },
                      selected: category == _category,
                      onTap: () => setState(() => _category = category),
                    ),
                ],
              ),
              if (statusMessage != null) ...[
                const SizedBox(height: 18),
                statusMessage,
              ],
            ],
          ),
        )),
        if (statusMessage == null) ...[
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (index > 0) Divider(color: context.colors.border, height: 1),
                ListeningRankRow(rank: index + 1, item: rows[index]),
              ],
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 150)),
      ],
    );
  }

  Iterable<ListeningRankItem> _rowsFor(ListeningStatsSnapshot stats) sync* {
    switch (_category) {
      case StatsCategory.tracks:
        for (final song in stats.songs) {
          yield ListeningRankItem(
            title: song.songTitle ?? 'Unknown Track',
            subtitle: song.songArtist ?? 'Unknown Artist',
            detail:
                '${song.playCount} ${song.playCount == 1 ? 'play' : 'plays'}, ${formatListeningTime(song.listenedMs)}',
            albumId: song.albumId,
            songId: song.songId,
          );
        }
      case StatsCategory.artists:
        for (final artist in stats.artists) {
          // Server credited-artist rollups don't carry a song count; show
          // plays instead of a misleading "0 tracks".
          yield ListeningRankItem(
            title: artist.name,
            subtitle: artist.uniqueSongs > 0
                ? '${artist.uniqueSongs} ${artist.uniqueSongs == 1 ? 'track' : 'tracks'}'
                : '${artist.playCount} ${artist.playCount == 1 ? 'play' : 'plays'}',
            detail:
                '${artist.playCount} ${artist.playCount == 1 ? 'play' : 'plays'}, ${formatListeningTime(artist.listenedMs)}',
            albumId: artist.artworkAlbumId,
            songId: artist.artworkSongId,
          );
        }
      case StatsCategory.albums:
        for (final album in stats.albums) {
          yield ListeningRankItem(
            title: album.title,
            subtitle: album.artist,
            detail: album.uniqueSongs > 0
                ? '${album.uniqueSongs} ${album.uniqueSongs == 1 ? 'track' : 'tracks'}, ${formatListeningTime(album.listenedMs)}'
                : '${album.playCount} ${album.playCount == 1 ? 'play' : 'plays'}, ${formatListeningTime(album.listenedMs)}',
            albumId: album.albumId.isEmpty ? null : album.albumId,
          );
        }
    }
  }

  /// One line describing the account's Spotify import: how much it holds,
  /// when it last landed, and the span of history it covers.
  String _spotifyImportLine(SpotifyImportStatus status) {
    final plays = formatCountWithCommas(status.plays);
    final imported =
        formatDashboardDateTime(millisToLocal(status.lastImportedAtMs));
    final from = formatDashboardDate(millisToLocal(status.oldestPlayAtMs));
    final to = formatDashboardDate(millisToLocal(status.newestPlayAtMs));
    return '$plays Spotify-imported ${status.plays == 1 ? 'play' : 'plays'} · '
        'last import $imported · covering $from – $to';
  }

  void _openShareDialog(ListeningStatsSnapshot stats) {
    final client = context.read<ConnectionController>().client;
    unawaited(showStatsShareDialog(
      context: context,
      initialCategory: _category,
      snapshot: StatsShareSnapshot(
        range: _range,
        songs: stats.songs.take(10).toList(),
        artists: stats.artists.take(10).toList(),
        albums: stats.albums.take(10).toList(),
        totalSongsCount: stats.songs.length,
        totalArtistsCount: stats.artists.length,
        totalAlbumsCount: stats.albums.length,
        totalListenedMs: stats.totalListenedMs,
        averageDailyMs: stats.averageDailyMs,
        playtimeUnit: _playtimeUnit,
        client: client,
      ),
    ));
  }

  /// Opens the Spotify-history import flow. The username doubles as the
  /// account's stable id baked into the imported events' deterministic ids.
  void _openSpotifyImport() {
    final connection = context.read<ConnectionController>();
    final client = connection.client;
    final username = connection.username;
    if (client == null || username == null || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to your server to import Spotify history.'),
        ),
      );
      return;
    }
    final host = maybeReadHost(context);
    final songs = context.read<LibraryController>().songs;
    unawaited(showDialog<void>(
      context: context,
      builder: (dialogContext) => SpotifyImportDialog(
        librarySongs: songs,
        accountUserId: username,
        apiClient: client,
        supportsListeningSourceReset:
            connection.serverInfo?.supportsListeningSourceReset ?? false,
        picker: host?.spotifyFilePicker,
        clientKind: host?.statsClientKind ?? 'web',
        onImported: () {
          if (!mounted) return;
          _refreshStatsViews();
        },
      ),
    ));
  }

  /// Shared post-import/post-undo stats refresh: imported (or removed)
  /// plays land in the account rollups immediately, so drop the memoized
  /// ranges to stop pre-change numbers lingering, then refetch the
  /// account view and the current period.
  void _refreshStatsViews() {
    _periodMemo.clear();
    _periodSnapshotFor = null;
    _periodSnapshotCache = null;
    unawaited(context.read<ListeningStatsController>().refreshAccountStats());
    if (!_range.isAllTime) unawaited(_loadPeriod());
  }

  /// Persistent counterpart to the import done-screen undo: removes every
  /// Spotify-imported play from the account via the safety-enforced
  /// [SpotifyImportController.undo] path.
  Future<void> _confirmRemoveSpotifyImport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Spotify import?'),
        content: const Text(
          'Every play imported from Spotify will be removed from this '
          'account. Your Ariami-tracked listening history is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Remove import',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Re-check the live state: the dialog may have outlived a disconnect,
    // an account switch, or a failed refresh.
    final connection = context.read<ConnectionController>();
    final statsController = context.read<ListeningStatsController>();
    final client = connection.client;
    if (client == null ||
        connection.serverInfo?.supportsListeningSourceReset != true ||
        !statsController.hasSpotifyImport ||
        statsController.accountStatsError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The Spotify import cannot currently be removed safely.',
          ),
        ),
      );
      return;
    }

    setState(() => _removingSpotifyImport = true);
    // A temporary controller reuses the existing safety-enforced undo path
    // (it refuses when the server never advertised source-reset support).
    final undoController =
        SpotifyImportController(supportsListeningSourceReset: true);
    try {
      await undoController.undo(
        client,
        accountUserId: connection.username ?? '',
      );
      if (!mounted) return;
      final deleted = undoController.undoDeletedCount;
      if (deleted != null) {
        // Flip the flag immediately so the action disappears even if the
        // refresh below races or fails.
        statsController.markSpotifyImportRemoved();
        _refreshStatsViews();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Removed $deleted Spotify-imported '
              '${deleted == 1 ? 'play' : 'plays'}.',
            ),
          ),
        );
      } else {
        final message = undoController.statusMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message.isNotEmpty
                  ? message
                  : 'Could not remove the Spotify import. Please try again.',
            ),
          ),
        );
      }
    } finally {
      undoController.dispose();
      if (mounted) setState(() => _removingSpotifyImport = false);
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset listening stats?'),
        content: const Text(
          'This permanently deletes your listening history for this account '
          'across all your devices. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Reset',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      await context.read<ListeningStatsController>().resetEverywhere();
      // Memoized ranges predate the wipe and must not resurrect old numbers.
      _periodMemo.clear();
      _periodSnapshotFor = null;
      _periodSnapshotCache = null;
      _periodStats = null;
      if (mounted && !_range.isAllTime) unawaited(_loadPeriod());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not reset listening stats. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }
}
