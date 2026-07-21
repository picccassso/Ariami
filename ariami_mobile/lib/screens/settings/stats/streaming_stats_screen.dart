import 'dart:async';

import '../../../utils/responsive.dart';

import 'package:ariami_core/ariami_core.dart' show ListeningPeriodStats;
import 'package:flutter/material.dart';
import '../../../models/api_models.dart';
import '../../../models/artist_stats.dart';
import '../../../services/stats/period_stats_loader.dart';
import '../../../services/stats/period_stats_cache.dart';
import '../../../services/stats/period_stats_overlay_apply.dart';
import '../../../services/stats/streaming_stats_service.dart';
import '../../../services/stats/account_stats_service.dart';
import '../../../services/stats/stats_artwork_resolver.dart';
import '../../../services/api/api_client.dart';
import '../../../services/api/connection_service.dart';
import '../../../widgets/common/mini_player_aware_bottom_sheet.dart';
import 'overview_metrics.dart';
import 'playtime_format.dart';
import 'widgets/widgets.dart';

/// Screen displaying streaming statistics and listening data.
///
/// Two data paths coexist:
/// - All-time: the existing local stats + account overlay (works offline,
///   includes this device's pending uploads). The Artists tab additionally
///   prefers the server's credited-artist rollups — where a play of "Mercy"
///   counts under Kanye West, Big Sean, Pusha T and 2 Chainz individually —
///   and falls back to local combined-string grouping when unavailable.
/// - Today / specific day / week / month / year: server/cache base plus a
///   display-only overlay of still-pending outbox events. The loader never
///   mutates the base; when the outbox changes the overlay recomputes
///   immediately offline. After sync, the server base is refreshed and
///   becomes source of truth again. A year that contains the complete known
///   history reuses all-time so imported baseline totals are not dropped.
///   With no base and no in-range pending events, the screen degrades to a
///   clear offline message.
class StreamingStatsScreen extends StatefulWidget {
  const StreamingStatsScreen({super.key});

  @override
  State<StreamingStatsScreen> createState() => _StreamingStatsScreenState();
}

class _StreamingStatsScreenState extends State<StreamingStatsScreen>
    with SingleTickerProviderStateMixin {
  final StreamingStatsService _statsService = StreamingStatsService();
  final ConnectionService _connectionService = ConnectionService();
  final AccountStatsService _accountStats = AccountStatsService();
  final PeriodStatsCache _periodCache = PeriodStatsCache();

  late TabController _tabController;
  late final PeriodStatsLoader _periodLoader;
  int _currentTabIndex = 0;

  StatsRange _range = StatsRange.specificDay(DateTime.now());
  /// Untouched server/cache snapshot for the selected period.
  ListeningPeriodStats? _periodBase;
  /// Displayed stats = base + pending outbox overlay.
  ListeningPeriodStats? _periodStats;
  bool _loadingPeriod = false;
  bool _periodUnavailable = false;
  int _periodRequestSeq = 0;
  Timer? _periodBaseRefreshDebounce;

  /// All-time credited artists from the server; null means unavailable
  /// (offline / old server) and the local grouping is shown instead.
  List<ArtistStats>? _creditedArtists;
  Map<String, AlbumModel> _albumsById = <String, AlbumModel>{};
  StatsArtworkResolver _artworkResolver = StatsArtworkResolver(
    albums: const <AlbumModel>[],
    songs: const <SongModel>[],
  );

  final PlaytimeFormat _playtime = PlaytimeFormat.load();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTabIndex = _tabController.index;
      });
    });
    _periodLoader = PeriodStatsLoader(
      fetchDay: (date, limit) => _requireClient().getListeningDay(
        date,
        limit: limit,
      ),
      fetchPeriod: (from, to, limit) => _requireClient().getListeningPeriod(
        from: from,
        to: to,
        limit: limit,
      ),
      fetchArtists: (limit) =>
          _requireClient().getListeningArtists(limit: limit),
      readCached: (from, to) {
        final scope = _periodCacheScope;
        if (scope == null) return Future<Map<String, dynamic>?>.value();
        return _periodCache.read(scope: scope, from: from, to: to);
      },
      writeCached: (from, to, stats) {
        final scope = _periodCacheScope;
        if (scope == null) return Future<void>.value();
        return _periodCache.write(
          scope: scope,
          from: from,
          to: to,
          stats: stats,
        );
      },
    );
    // Period overlay tracks pending outbox membership immediately.
    _accountStats.addListener(_onPendingListeningChanged);
    // Request fresh data when screen loads (local instantly, account-wide
    // refresh in the background).
    _statsService.refreshTopSongs();
    _accountStats.refreshSummary();
    _refreshCreditedArtists();
    _loadAlbumMetadata();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPeriod();
    });
  }

  Future<void> _loadAlbumMetadata() async {
    try {
      final library =
          await _connectionService.libraryReadFacade.getLibraryBundle();
      if (!mounted) return;
      setState(() {
        _albumsById = {for (final album in library.albums) album.id: album};
        _artworkResolver = StatsArtworkResolver(
          albums: library.albums,
          songs: library.songs,
        );
      });
    } catch (_) {
      // Stats remain usable offline; metadata will be shown when already
      // present in the stored event/rollup.
    }
  }

  ApiClient _requireClient() {
    final client = _connectionService.apiClient;
    if (client == null) {
      throw StateError('Not connected to a server');
    }
    return client;
  }

  String? get _periodCacheScope => PeriodStatsCache.scopeFor(
        userId: _connectionService.userId,
        serverInfo: _connectionService.serverInfo,
      );

  @override
  void dispose() {
    _periodBaseRefreshDebounce?.cancel();
    _accountStats.removeListener(_onPendingListeningChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// Pending outbox changed: recompute period overlay immediately (no network).
  /// When online, also debounced-refresh the server base so truth replaces the
  /// overlay after events drain — without blocking the instant recompute.
  void _onPendingListeningChanged() {
    if (!mounted || _range.isAllTime) return;
    _applyPeriodOverlay();
    if (_connectionService.isConnected && _connectionService.isAuthenticated) {
      _schedulePeriodBaseRefresh();
    }
  }

  void _schedulePeriodBaseRefresh() {
    _periodBaseRefreshDebounce?.cancel();
    _periodBaseRefreshDebounce = Timer(const Duration(seconds: 1), () {
      _periodBaseRefreshDebounce = null;
      if (mounted && !_range.isAllTime) unawaited(_loadPeriod());
    });
  }

  /// Recomputes displayed period stats from [_periodBase] + pending events.
  void _applyPeriodOverlay() {
    final range = _range;
    if (range.isAllTime) return;
    final bounds = range.bounds();
    if (bounds == null) {
      if (!mounted) return;
      setState(() {
        _periodStats = null;
        _periodUnavailable = true;
      });
      return;
    }
    final pending = _accountStats.pendingListeningEvents;
    final displayed = buildDisplayedPeriodStats(
      base: _periodBase,
      pending: pending,
      fromDay: bounds.from,
      toDay: bounds.to,
      ackedInFlightEventIds: _accountStats.syncedPendingEventIds,
    );
    if (!mounted) return;
    setState(() {
      _periodStats = displayed;
      // Offline fallback only when there is no base and nothing useful to show
      // from pending events in range.
      _periodUnavailable =
          _periodBase == null && !periodStatsHasContent(displayed);
    });
  }

  Future<void> _refreshCreditedArtists() async {
    final rollups = await _periodLoader.loadAllTimeArtists();
    if (!mounted) return;
    setState(() {
      _creditedArtists = rollups == null
          ? null
          : artistStatsFromCredited(rollups, _statsService.getAllStats());
    });
  }

  void _selectRange(StatsRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _periodBase = null;
      _periodStats = null;
      _periodUnavailable = false;
    });
    if (!range.isAllTime) _loadPeriod();
  }

  /// Switches granularity from the bottom bar. Re-tapping DAY opens the
  /// date picker; everything else jumps to the current calendar unit.
  void _selectGranularity(StatsRangeKind kind) {
    final now = DateTime.now();
    switch (kind) {
      case StatsRangeKind.all:
        _selectRange(StatsRange.all);
      case StatsRangeKind.today:
      case StatsRangeKind.day:
        if (_range.isSingleDay) {
          _pickSpecificDay();
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
    DateTime? earliest;
    for (final stat in _statsService.getAllStats()) {
      final first = stat.firstPlayed;
      if (first != null && (earliest == null || first.isBefore(earliest))) {
        earliest = first;
      }
    }
    return earliest == null ? null : StatsRange.formatLocalDay(earliest);
  }

  /// A baseline import has honest all-time totals but no daily distribution.
  /// When every recorded first/last timestamp is inside the selected year,
  /// that all-time snapshot is also the complete year snapshot.
  bool _yearCoversAllHistory() {
    if (_range.kind != StatsRangeKind.year) return false;
    final stats = _statsService.getAllStats();
    if (stats.isEmpty) return false;
    DateTime? firstPlayed;
    DateTime? lastPlayed;
    for (final stat in stats) {
      final first = stat.firstPlayed;
      final last = stat.lastPlayed;
      if (first == null || last == null) return false;
      if (firstPlayed == null || first.isBefore(firstPlayed)) {
        firstPlayed = first;
      }
      if (lastPlayed == null || last.isAfter(lastPlayed)) {
        lastPlayed = last;
      }
    }
    return _range.coversHistory(
      firstPlayed: firstPlayed,
      lastPlayed: lastPlayed,
    );
  }

  bool get _useAllTimeData => _range.isAllTime || _yearCoversAllHistory();

  Future<void> _loadPeriod() async {
    final range = _range;
    if (range.isAllTime) return;
    final seq = ++_periodRequestSeq;
    setState(() {
      _loadingPeriod = true;
      _periodUnavailable = false;
    });
    // When online, drain accepted uploads first so the fresh base is less
    // likely to race with still-pending outbox rows.
    if (_connectionService.isConnected && _connectionService.isAuthenticated) {
      await _accountStats.syncPendingEventsNow();
    }
    if (!mounted || seq != _periodRequestSeq || range != _range) return;
    // Stale-while-revalidate: a previously viewed range renders from cache
    // instantly while the fresh fetch replaces it below. Overlay is applied
    // on top of the base so pending local events show offline immediately.
    final cached = await _periodLoader.loadCached(range);
    if (mounted &&
        seq == _periodRequestSeq &&
        range == _range &&
        cached != null) {
      _periodBase = cached;
      _applyPeriodOverlay();
    }
    final stats = await _periodLoader.load(range);
    if (!mounted || seq != _periodRequestSeq || range != _range) return;
    _periodBase = stats ?? cached;
    _loadingPeriod = false;
    _applyPeriodOverlay();
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
    if (picked == null) return;
    _selectRange(StatsRange.specificDay(picked));
  }

  void _onPlaytimeTap() {
    var firstTap = false;
    setState(() {
      firstTap = _playtime.advance();
    });
    if (firstTap) showPlaytimeHintDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listening Stats'),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: isDark ? Colors.white : Colors.black,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: isDark ? Colors.white : Colors.black,
          unselectedLabelColor: Colors.grey[600],
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'TRACKS'),
            Tab(text: 'ARTISTS'),
            Tab(text: 'ALBUMS'),
          ],
        ),
      ),
      body: ContentWidthLimiter(
          child: Stack(
        children: [
          RefreshIndicator(
            color: isDark ? Colors.white : Colors.black,
            backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
            onRefresh: () async {
              await _accountStats.refreshSummary();
              await _refreshCreditedArtists();
              if (!_range.isAllTime) await _loadPeriod();
              if (mounted) setState(() {});
            },
            child: Column(
              children: [
                // Overview card with totals (dynamic based on tab and range)
                _buildOverviewCard(),

                // Tab content
                Expanded(
                  child: ListenableBuilder(
                    listenable: _statsService,
                    builder: (context, _) => TabBarView(
                      controller: _tabController,
                      children: _useAllTimeData
                          ? [
                              StatsTracksTab(
                                statsService: _statsService,
                                artworkResolver: _artworkResolver,
                              ),
                              StatsArtistsTab(
                                statsService: _statsService,
                                creditedArtists: _creditedArtists,
                                artworkResolver: _artworkResolver,
                              ),
                              StatsAlbumsTab(
                                statsService: _statsService,
                                artworkResolver: _artworkResolver,
                                albumsById: _albumsById,
                              ),
                            ]
                          : [
                              _buildPeriodTab(0),
                              _buildPeriodTab(1),
                              _buildPeriodTab(2),
                            ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Floating period selector, pinned above the mini player / nav
          // chrome: ‹ period › stepper plus a granularity row.
          Align(
            alignment: Alignment.bottomCenter,
            child: MiniPlayerAwareBuilder(
              builder: (context, bottomPadding) => Padding(
                padding: EdgeInsets.only(bottom: bottomPadding + 8),
                child: StatsPeriodSelector(
                  range: _range,
                  canStepBack:
                      _range.isSteppable && _range.canStepBack(_earliestDay()),
                  canStepForward: _range.isSteppable && _range.canStepForward(),
                  onStep: _step,
                  onPickDay: _pickSpecificDay,
                  onSelectGranularity: _selectGranularity,
                ),
              ),
            ),
          ),
        ],
      )),
    );
  }

  Widget _buildOverviewCard() {
    return ListenableBuilder(
      listenable: _statsService,
      builder: (context, _) => StatsOverviewCard(
        metrics: computeOverviewMetrics(
          tabIndex: _currentTabIndex,
          useAllTimeData: _useAllTimeData,
          periodStats: _periodStats,
          statsService: _statsService,
          creditedArtists: _creditedArtists,
          playtime: _playtime,
        ),
        onPlaytimeTap: _onPlaytimeTap,
        showTapHint: _playtime.hintPending,
      ),
    );
  }

  Widget _buildPeriodTab(int tab) => StatsPeriodTab(
        tab: tab,
        loading: _loadingPeriod,
        unavailable: _periodUnavailable,
        stats: _periodStats,
        artworkResolver: _artworkResolver,
        albumsById: _albumsById,
      );
}
