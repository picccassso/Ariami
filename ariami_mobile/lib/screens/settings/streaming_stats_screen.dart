import '../../utils/responsive.dart';
import 'dart:async';

import 'package:ariami_core/ariami_core.dart' show ListeningPeriodStats;
import 'package:flutter/material.dart';
import '../../models/song_stats.dart';
import '../../models/artist_stats.dart';
import '../../models/album_stats.dart';
import '../../models/api_models.dart';
import '../../services/stats/period_stats_loader.dart';
import '../../services/stats/period_stats_cache.dart';
import '../../services/stats/streaming_stats_service.dart';
import '../../services/stats/account_stats_service.dart';
import '../../services/stats/stats_artwork_resolver.dart';
import '../../services/api/api_client.dart';
import '../../services/api/connection_service.dart';
import '../../utils/shared_preferences_cache.dart';
import '../../widgets/common/cached_artwork.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';

/// Screen displaying streaming statistics and listening data.
///
/// Two data paths coexist:
/// - All-time: the existing local stats + account overlay (works offline,
///   includes this device's pending uploads). The Artists tab additionally
///   prefers the server's credited-artist rollups — where a play of "Mercy"
///   counts under Kanye West, Big Sean, Pusha T and 2 Chainz individually —
///   and falls back to local combined-string grouping when unavailable.
/// - Today / specific day / week / month / year: normally served by the
///   server's day/period endpoints. A year that contains the complete known
///   history reuses all-time so imported baseline totals are not dropped.
///   Other periods reflect synced events only and persist exact-range
///   snapshots for offline viewing. With no cached snapshot, the screen
///   degrades to a clear message.
/// How PLAYTIME (and AVG DAILY) render their durations. Tapping the metric
/// cycles through these in order and the choice is remembered.
enum _PlaytimeUnit { hours, minutes, minutesCompact }

class StreamingStatsScreen extends StatefulWidget {
  const StreamingStatsScreen({super.key});

  @override
  State<StreamingStatsScreen> createState() => _StreamingStatsScreenState();
}

class _StreamingStatsScreenState extends State<StreamingStatsScreen>
    with SingleTickerProviderStateMixin {
  final StreamingStatsService _statsService = StreamingStatsService();
  final ConnectionService _connectionService = ConnectionService();
  final PeriodStatsCache _periodCache = PeriodStatsCache();

  late TabController _tabController;
  late final PeriodStatsLoader _periodLoader;
  int _currentTabIndex = 0;

  StatsRange _range = StatsRange.specificDay(DateTime.now());
  ListeningPeriodStats? _periodStats;
  bool _loadingPeriod = false;
  bool _periodUnavailable = false;
  int _periodRequestSeq = 0;

  /// All-time credited artists from the server; null means unavailable
  /// (offline / old server) and the local grouping is shown instead.
  List<ArtistStats>? _creditedArtists;
  Map<String, AlbumModel> _albumsById = <String, AlbumModel>{};
  StatsArtworkResolver _artworkResolver = StatsArtworkResolver(
    albums: const <AlbumModel>[],
    songs: const <SongModel>[],
  );

  /// PLAYTIME (and AVG DAILY, when shown) cycle through hours, minutes, and
  /// compact minutes when the PLAYTIME metric is tapped. Until the very first
  /// tap a little finger demonstrates the gesture on the metric, and that
  /// first tap triggers a one-time explainer dialog.
  static const String _playtimeHintSeenKey = 'stats_playtime_hint_seen';
  static const String _playtimeUnitKey = 'stats_playtime_unit';
  _PlaytimeUnit _playtimeUnit = _PlaytimeUnit.hours;
  bool _playtimeHintPending = false;

  /// PLAYTIME total (ms) for the currently shown view, recorded while
  /// formatting so the tap handler can skip compact minutes when it wouldn't
  /// differ from plain minutes (i.e. under 1000 minutes).
  int _playtimeTotalMs = 0;

  @override
  void initState() {
    super.initState();
    final unitIndex = sharedPrefs.getInt(_playtimeUnitKey) ?? 0;
    _playtimeUnit = _PlaytimeUnit
        .values[unitIndex.clamp(0, _PlaytimeUnit.values.length - 1)];
    _playtimeHintPending =
        !(sharedPrefs.getBool(_playtimeHintSeenKey) ?? false);
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
    // Request fresh data when screen loads (local instantly, account-wide
    // refresh in the background).
    _statsService.refreshTopSongs();
    AccountStatsService().refreshSummary();
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

  String _albumName(AlbumStats stat) =>
      stat.albumName ?? _albumsById[stat.albumId]?.title ?? 'Unknown Album';

  String _albumArtist(AlbumStats stat) =>
      stat.albumArtist ?? _albumsById[stat.albumId]?.artist ?? 'Unknown Artist';

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
    _tabController.dispose();
    super.dispose();
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
    final stats = await _periodLoader.load(range);
    if (!mounted || seq != _periodRequestSeq || range != _range) return;
    setState(() {
      _loadingPeriod = false;
      _periodStats = stats;
      _periodUnavailable = stats == null;
    });
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
              await AccountStatsService().refreshSummary();
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
                              _buildTracksTab(),
                              _buildArtistsTab(),
                              _buildAlbumsTab(),
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
                child: _buildPeriodSelector(),
              ),
            ),
          ),
        ],
      )),
    );
  }

  /// The scroll inset that keeps list content clear of the floating period
  /// selector plus the global bottom chrome.
  static const double _listBottomInset = 240;

  /// stats.fm-style period selector: a ‹ label › stepper over a
  /// Day / Week / Month / Year / All granularity row. Paging is blocked
  /// past today and before the account's first listen.
  Widget _buildPeriodSelector() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final range = _range;
    final canBack = range.isSteppable && range.canStepBack(_earliestDay());
    final canForward = range.isSteppable && range.canStepForward();
    final granularities = <(StatsRangeKind, String)>[
      (StatsRangeKind.day, 'DAY'),
      (StatsRangeKind.week, 'WEEK'),
      (StatsRangeKind.month, 'MONTH'),
      (StatsRangeKind.year, 'YEAR'),
      (StatsRangeKind.all, 'ALL'),
    ];
    bool isSelected(StatsRangeKind kind) => switch (kind) {
          StatsRangeKind.day => range.isSingleDay,
          _ => range.kind == kind,
        };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _StepChevron(
                icon: Icons.chevron_left_rounded,
                enabled: canBack,
                colorScheme: colorScheme,
                onTap: () => _step(-1),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Tapping the label jumps straight to the date picker in
                  // day mode.
                  onTap: range.isSingleDay ? _pickSpecificDay : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          range.title(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (range.isSingleDay) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              _StepChevron(
                icon: Icons.chevron_right_rounded,
                enabled: canForward,
                colorScheme: colorScheme,
                onTap: () => _step(1),
              ),
            ],
          ),
          Row(
            children: [
              for (final entry in granularities)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _RangeChip(
                      label: entry.$2,
                      selected: isSelected(entry.$1),
                      onTap: () => _selectGranularity(entry.$1),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build the overview card showing total stats (dynamic based on tab)
  Widget _buildOverviewCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: _statsService,
      builder: (context, _) {
        String metric1Label;
        String metric1Value;
        String metric2Label;
        String metric2Value;
        String metric3Label;
        String metric3Value;

        if (!_useAllTimeData) {
          final stats = _periodStats;
          metric1Label = switch (_currentTabIndex) {
            1 => 'ARTISTS',
            2 => 'ALBUMS',
            _ => 'SONGS',
          };
          metric1Value = switch (_currentTabIndex) {
            1 => '${stats?.artists.length ?? 0}',
            2 => '${stats?.albums.length ?? 0}',
            _ => '${stats?.songs.length ?? 0}',
          };
          metric2Label = 'PLAYTIME';
          metric2Value = _formatPlaytime(
              Duration(milliseconds: stats?.totalListenedMs ?? 0));
          metric3Label = 'PLAYS';
          metric3Value = '${stats?.totalPlays ?? 0}';
        } else {
          switch (_currentTabIndex) {
            case 0: // Tracks
              final stats = _statsService.getTotalStats();
              final avgData = _statsService.getAverageDailyTime();
              metric1Label = 'SONGS';
              metric1Value = stats.totalSongsPlayed.toString();
              metric2Label = 'PLAYTIME';
              metric2Value = _formatPlaytime(stats.totalTimeStreamed);
              metric3Label = 'AVG DAILY';
              metric3Value = _formatDurationShort(avgData.perCalendarDay);
              break;

            case 1: // Artists
              final avgData = _statsService.getAverageDailyTime();
              final credited = _creditedArtists;
              final artistCount = credited != null
                  ? credited.length
                  : _statsService.getTopArtists(limit: 1000).length;
              // With credited artists every collaborator receives the full
              // listened time, so summing per-artist time would double-count
              // collabs — the account total is the honest playtime figure.
              final totalTime = credited != null
                  ? _statsService.getTotalStats().totalTimeStreamed
                  : _statsService.getTopArtists(limit: 1000).fold<Duration>(
                        Duration.zero,
                        (sum, artist) => sum + artist.totalTime,
                      );
              metric1Label = 'ARTISTS';
              metric1Value = artistCount.toString();
              metric2Label = 'PLAYTIME';
              metric2Value = _formatPlaytime(totalTime);
              metric3Label = 'AVG DAILY';
              metric3Value = _formatDurationShort(avgData.perCalendarDay);
              break;

            case 2: // Albums
              final avgData = _statsService.getAverageDailyTime();
              final albums = _statsService.getTopAlbums(limit: 1000);
              final totalTime = albums.fold<Duration>(
                Duration.zero,
                (sum, album) => sum + album.totalTime,
              );
              metric1Label = 'ALBUMS';
              metric1Value = albums.length.toString();
              metric2Label = 'PLAYTIME';
              metric2Value = _formatPlaytime(totalTime);
              metric3Label = 'AVG DAILY';
              metric3Value = _formatDurationShort(avgData.perCalendarDay);
              break;

            default:
              metric1Label = 'SONGS';
              metric1Value = '0';
              metric2Label = 'PLAYTIME';
              _playtimeTotalMs = 0;
              metric2Value = '0h';
              metric3Label = 'AVG';
              metric3Value = '0m';
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                    label: metric1Label, value: metric1Value, isDark: isDark),
                // metric2 is always PLAYTIME; tapping it flips the units.
                _buildStatItem(
                  label: metric2Label,
                  value: metric2Value,
                  isDark: isDark,
                  onTap: _onPlaytimeTap,
                  pulse: _playtimeHintPending,
                ),
                _buildStatItem(
                    label: metric3Label, value: metric3Value, isDark: isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Formats the PLAYTIME total and records it so the tap handler can skip
  /// compact minutes when it wouldn't differ from plain minutes.
  String _formatPlaytime(Duration duration) {
    _playtimeTotalMs = duration.inMilliseconds;
    return _formatDurationShort(duration);
  }

  String _formatDurationShort(Duration duration) {
    switch (_playtimeUnit) {
      case _PlaytimeUnit.minutes:
        return '${duration.inMinutes}m';
      case _PlaytimeUnit.minutesCompact:
        return _formatMinutesCompact(duration);
      case _PlaytimeUnit.hours:
        if (duration.inHours > 0) {
          return '${duration.inHours}h';
        }
        return '${duration.inMinutes}m';
    }
  }

  /// Compact minutes (e.g. 4221 → "4.2k"). Values under 1000 stay exact; the
  /// trailing ".0" is trimmed so 45000 reads "45k".
  String _formatMinutesCompact(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 1000) return '${minutes}m';
    var text = (minutes / 1000).toStringAsFixed(1);
    if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
    return '${text}k';
  }

  /// The next unit in the cycle, skipping compact minutes when it would render
  /// identically to plain minutes (under 1000 minutes) so the user never taps
  /// through a no-op change on the way back to hours.
  _PlaytimeUnit _nextPlaytimeUnit(_PlaytimeUnit current) {
    var next = _PlaytimeUnit
        .values[(current.index + 1) % _PlaytimeUnit.values.length];
    if (next == _PlaytimeUnit.minutesCompact &&
        Duration(milliseconds: _playtimeTotalMs).inMinutes < 1000) {
      next = _PlaytimeUnit.hours;
    }
    return next;
  }

  void _onPlaytimeTap() {
    final firstTap = _playtimeHintPending;
    setState(() {
      _playtimeUnit = _nextPlaytimeUnit(_playtimeUnit);
      _playtimeHintPending = false;
    });
    unawaited(sharedPrefs.setInt(_playtimeUnitKey, _playtimeUnit.index));
    if (!firstTap) return;
    unawaited(sharedPrefs.setBool(_playtimeHintSeenKey, true));
    _showPlaytimeHintDialog();
  }

  /// One-time explainer shown right after the first PLAYTIME tap, so the
  /// value switching units doesn't read as a glitch.
  void _showPlaytimeHintDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
        title: Text(
          'PLAYTIME UNITS',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Text(
          'Tapping PLAYTIME cycles it through hours, minutes, and compact '
          'minutes — AVG DAILY follows along when it\'s shown. Keep tapping '
          'to move through them.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'GOT IT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single stat item in the grid
  Widget _buildStatItem({
    required String label,
    required String value,
    required bool isDark,
    String? secondaryValue,
    VoidCallback? onTap,
    bool pulse = false,
  }) {
    Widget item = Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.grey[500] : Colors.grey[600],
            letterSpacing: 1.0,
          ),
        ),
        if (secondaryValue != null) ...[
          const SizedBox(height: 4),
          Text(
            secondaryValue,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[700] : Colors.grey[400],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
    if (pulse) item = _TapHint(child: item);
    if (onTap != null) {
      item = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: item,
      );
    }
    return item;
  }

  /// One tab (0=tracks, 1=artists, 2=albums) for a server-derived period.
  Widget _buildPeriodTab(int tab) {
    if (_loadingPeriod && _periodStats == null) {
      return _buildLoadingState();
    }
    if (_periodUnavailable) {
      return _buildEmptyState(
        'Stats for this period need a connection to your server '
        '(and a server that supports period stats).',
        icon: Icons.cloud_off_rounded,
      );
    }
    final stats = _periodStats;
    if (stats == null) return _buildLoadingState();

    final title = switch (tab) {
      1 => 'TOP ARTISTS',
      2 => 'TOP ALBUMS',
      _ => 'TOP SONGS',
    };
    final rows = switch (tab) {
      1 => [
          for (final (index, stat) in artistStatsFromCredited(
            stats.artists,
            songStatsFromRollups(stats.songs),
          ).indexed)
            _buildTopArtistItem(stat, index + 1),
        ],
      2 => [
          for (final (index, stat)
              in albumStatsFromRollups(stats.albums).indexed)
            _buildTopAlbumItem(stat, index + 1),
        ],
      _ => [
          for (final (index, stat) in songStatsFromRollups(stats.songs).indexed)
            _buildTopSongItem(stat, index + 1),
        ],
    };

    if (rows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: _listBottomInset),
        children: [
          const SizedBox(height: 40),
          _buildEmptyState('No listening in this period yet.'),
        ],
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.only(bottom: _listBottomInset),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  /// Build the tracks tab
  Widget _buildTracksTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.only(bottom: _listBottomInset),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            'TOP SONGS',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<SongStats>>(
          stream: _statsService.topSongsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState();
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return _buildLoadingState();
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyState(
                  'No stats yet. Start listening to see your top songs!');
            }

            final topSongs = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topSongs.length,
              itemBuilder: (context, index) {
                final stat = topSongs[index];
                return _buildTopSongItem(stat, index + 1);
              },
            );
          },
        ),
      ],
    );
  }

  /// Build the artists tab. Prefers the server's credited-artist rollups
  /// (each collaborator on a multi-artist track counted individually) and
  /// falls back to local combined-string grouping when unavailable.
  Widget _buildArtistsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final credited = _creditedArtists;
    return ListView(
      padding: const EdgeInsets.only(bottom: _listBottomInset),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            'TOP ARTISTS',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (credited != null)
          credited.isEmpty
              ? _buildEmptyState(
                  'No stats yet. Start listening to see your top artists!')
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: credited.length,
                  itemBuilder: (context, index) {
                    final stat = credited[index];
                    return _buildTopArtistItem(stat, index + 1);
                  },
                )
        else
          StreamBuilder<List<ArtistStats>>(
            stream: _statsService.topArtistsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _buildErrorState();
              }

              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return _buildLoadingState();
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return _buildEmptyState(
                    'No stats yet. Start listening to see your top artists!');
              }

              final topArtists = snapshot.data!;
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: topArtists.length,
                itemBuilder: (context, index) {
                  final stat = topArtists[index];
                  return _buildTopArtistItem(stat, index + 1);
                },
              );
            },
          ),
      ],
    );
  }

  /// Build the albums tab
  Widget _buildAlbumsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.only(bottom: _listBottomInset),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            'TOP ALBUMS',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<AlbumStats>>(
          stream: _statsService.topAlbumsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState();
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return _buildLoadingState();
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyState(
                  'No stats yet. Start listening to see your top albums!');
            }

            final topAlbums = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topAlbums.length,
              itemBuilder: (context, index) {
                final stat = topAlbums[index];
                return _buildTopAlbumItem(stat, index + 1);
              },
            );
          },
        ),
      ],
    );
  }

  /// Build reusable error state
  Widget _buildErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: isDark ? Colors.grey[800] : Colors.grey[200]),
          const SizedBox(height: 16),
          Text(
            'Error loading statistics',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  /// Build reusable loading state
  Widget _buildLoadingState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: CircularProgressIndicator(
        color: isDark ? Colors.white : Colors.black,
        strokeWidth: 2,
      ),
    );
  }

  /// Build reusable empty state
  Widget _buildEmptyState(String message, {IconData? icon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.music_note_rounded,
              size: 48, color: isDark ? Colors.grey[800] : Colors.grey[200]),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single top song item
  Widget _buildTopSongItem(SongStats stat, int rank) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final artwork = _artworkResolver.forSong(stat);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.grey[700] : Colors.grey[400],
                letterSpacing: -0.5,
              ),
            ),
          ),

          // Album artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedArtwork(
              albumId: artwork.cacheId,
              artworkUrl: artwork.artworkUrl,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              fallbackIconSize: 24,
              sizeHint: ArtworkSizeHint.thumbnail,
            ),
          ),
          const SizedBox(width: 16),

          // Song info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.songTitle ?? 'Unknown Track',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  stat.songArtist ?? 'Unknown Artist',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '${stat.playCount} PLAYS • ${stat.formattedTime.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single top artist item
  Widget _buildTopArtistItem(ArtistStats stat, int rank) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final artwork = _artworkResolver.forArtist(stat);

    // Credited-artist rollups don't carry a song count; fall back to plays.
    final subtitle = stat.uniqueSongsCount > 0
        ? '${stat.uniqueSongsCount} ${stat.uniqueSongsCount == 1 ? 'SONG' : 'SONGS'}'
        : '${stat.playCount} ${stat.playCount == 1 ? 'PLAY' : 'PLAYS'}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.grey[700] : Colors.grey[400],
                letterSpacing: -0.5,
              ),
            ),
          ),

          // Artist artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedArtwork(
              albumId: artwork.cacheId,
              artworkUrl: artwork.artworkUrl,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              fallbackIcon: Icons.person_rounded,
              fallbackIconSize: 24,
              sizeHint: ArtworkSizeHint.thumbnail,
            ),
          ),
          const SizedBox(width: 16),

          // Artist info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.artistName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${stat.playCount} PLAYS • ${stat.formattedTime.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single top album item
  Widget _buildTopAlbumItem(AlbumStats stat, int rank) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final artwork = _artworkResolver.forAlbum(stat);
    // Period rollups don't carry a song count; fall back to plays.
    final detail = stat.uniqueSongsCount > 0
        ? '${stat.uniqueSongsCount} ${stat.uniqueSongsCount == 1 ? 'SONG' : 'SONGS'}'
        : '${stat.playCount} ${stat.playCount == 1 ? 'PLAY' : 'PLAYS'}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.grey[700] : Colors.grey[400],
                letterSpacing: -0.5,
              ),
            ),
          ),

          // Album artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedArtwork(
              albumId: artwork.cacheId,
              artworkUrl: artwork.artworkUrl,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              fallbackIconSize: 24,
              sizeHint: ArtworkSizeHint.thumbnail,
            ),
          ),
          const SizedBox(width: 16),

          // Album info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _albumName(stat),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _albumArtist(stat),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '$detail • ${stat.formattedTime.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                    letterSpacing: 0.5,
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

/// Overlays a little finger that periodically taps the child — the metric
/// dips under the press and a ripple ring expands, demonstrating the real
/// gesture. Only mounted while the PLAYTIME hint is still pending.
class _TapHint extends StatefulWidget {
  const _TapHint({required this.child});

  final Widget child;

  @override
  State<_TapHint> createState() => _TapHintState();
}

class _TapHintState extends State<_TapHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  /// Progress of [t] through the [from]→[to] slice of the loop, curved.
  static double _seg(double t, double from, double to, Curve curve) =>
      curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        // Loop: finger slides in (0–.25), presses (.25–.35), ripple +
        // release (.35–.7), fades out (.7–.85), rests (.85–1).
        final approach = _seg(t, 0.0, 0.25, Curves.easeOutCubic);
        final press = t < 0.25
            ? 0.0
            : t < 0.35
                ? _seg(t, 0.25, 0.35, Curves.easeIn)
                : 1.0 - _seg(t, 0.35, 0.5, Curves.easeOut);
        final ripple = _seg(t, 0.33, 0.7, Curves.easeOut);
        final visible = approach * (1.0 - _seg(t, 0.7, 0.85, Curves.easeIn));

        // Where the fake tap lands, relative to the metric's centre.
        const target = Offset(14, -6);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.scale(scale: 1.0 - 0.06 * press, child: child),
            Positioned.fill(
              child: IgnorePointer(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    if (ripple > 0 && ripple < 1)
                      Transform.translate(
                        offset: target,
                        child: Opacity(
                          opacity: (1.0 - ripple) * 0.7,
                          child: Container(
                            width: 8 + 26 * ripple,
                            height: 8 + 26 * ripple,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: color, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    Transform.translate(
                      // Fingertip sits just under the tap point; slides in
                      // from below-right and dips slightly on the press.
                      offset: target +
                          Offset(
                            6 + 20 * (1 - approach),
                            12 + 16 * (1 - approach) - 2 * press,
                          ),
                      child: Opacity(
                        opacity: visible.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 1.0 - 0.15 * press,
                          child: Icon(
                            Icons.touch_app_rounded,
                            size: 22,
                            color: color,
                            shadows: const [
                              Shadow(color: Colors.black38, blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A small pill for the granularity row.
class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? colorScheme.onSecondary : colorScheme.onSurfaceVariant;
    final background = selected ? colorScheme.secondary : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

/// A ‹ / › paging chevron for the period stepper; greyed out at the bounds
/// of the account's listening history.
class _StepChevron extends StatelessWidget {
  const _StepChevron({
    required this.icon,
    required this.enabled,
    required this.colorScheme,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.35);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 26, color: color),
      ),
    );
  }
}
