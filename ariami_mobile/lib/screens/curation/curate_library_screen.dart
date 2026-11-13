import 'dart:async';

import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:ariami_core/services/playlists/created_playlist_id.dart';
import 'package:ariami_core/services/search/search.dart';
import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../services/curation/library_curation_service.dart';
import '../../utils/constants.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../main/library/library_controller.dart';
import 'widgets/alphabet_scrubber.dart';
import 'widgets/artist_detail_sheet.dart';
import 'widgets/curation_mode_sheet.dart';
import 'widgets/curation_rows.dart';

/// Shows the one-time first-sign-in curation prompt for non-owner users.
Future<void> showMobileCurationOnboardingSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.library_music_rounded,
                  color: colors.textPrimary,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Set Up Your Library',
                    style: AppTheme.heading(22, color: colors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Choose how your personal library starts on this server. You can '
              'change this anytime from Library Options or Settings.',
              style: TextStyle(
                fontSize: 13.5,
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            _OnboardingChoiceCard(
              icon: Icons.all_inclusive_rounded,
              title: 'Include Everything',
              subtitle:
                  'Show the full server catalog and new music automatically. '
                  'You can still exclude individual artists or albums.',
              onTap: () => Navigator.of(sheetContext).pop('full'),
            ),
            const SizedBox(height: 12),
            _OnboardingChoiceCard(
              icon: Icons.tune_rounded,
              title: 'Pick My Artists & Albums',
              subtitle:
                  'Start clean and choose the specific artists, albums, server '
                  'playlists, and songs you want in your library.',
              onTap: () => Navigator.of(sheetContext).pop('curate'),
            ),
          ],
        ),
      );
    },
  );

  if (!context.mounted) return;
  if (choice == 'full') {
    try {
      await LibraryCurationService().completeOnboardingFull();
    } catch (_) {}
  } else if (choice == 'curate') {
    await CurateLibraryScreen.open(
      context,
      initialModeOverride: LibraryCurationMode.curated,
    );
  }
}

class _OnboardingChoiceCard extends StatelessWidget {
  const _OnboardingChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surfaceHigh,
      borderRadius: BorderRadius.circular(AppTheme.panelRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.panelRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.panelRadius),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colors.textPrimary, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CurateTab { artists, albums, playlists, songs }

enum _CurationStatusFilter { all, included, excluded }

enum _OverflowMenuAction { includeAll, clearAll }

class CurateLibraryScreen extends StatefulWidget {
  const CurateLibraryScreen({
    super.key,
    this.initialModeOverride,
  });

  final LibraryCurationMode? initialModeOverride;

  /// Pushes [CurateLibraryScreen] on the root navigator so the mini player and
  /// bottom navigation bar stay hidden while curating.
  static Future<bool?> open(
    BuildContext context, {
    LibraryCurationMode? initialModeOverride,
  }) {
    return Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => CurateLibraryScreen(
          initialModeOverride: initialModeOverride,
        ),
      ),
    );
  }

  @override
  State<CurateLibraryScreen> createState() => _CurateLibraryScreenState();
}

class _CurateLibraryScreenState extends State<CurateLibraryScreen>
    with SingleTickerProviderStateMixin {
  final LibraryController _library = LibraryController();
  final LibraryCurationService _curationService = LibraryCurationService();
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;

  late CurationDraft _draft;
  String _initialSnapshot = '';

  List<CurationArtistGroup> _artistGroups = const <CurationArtistGroup>[];
  List<AlbumModel> _albumsSorted = const <AlbumModel>[];
  List<CurationCatalogPlaylist> _playlistsSorted =
      const <CurationCatalogPlaylist>[];
  List<SongModel> _allSongsSorted = const <SongModel>[];

  Map<String, List<CurationCatalogSong>> _songsByAlbum = const {};
  Map<String, String> _albumArtistById = const {};
  Map<String, String> _albumTitleById = const {};
  Map<String, List<String>> _playlistAlbumIdsById = const {};

  _CurateTab _tab = _CurateTab.artists;
  _CurationStatusFilter _statusFilter = _CurationStatusFilter.all;
  String? _selectedArtistKey;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _CurateTab.values.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final nextTab = _CurateTab.values[_tabController.index];
    if (nextTab != _tab) {
      setState(() => _tab = nextTab);
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _curationService.loadFromServer();
      if (!_library.hasRawCatalog) {
        await _library.refreshLibrary();
      }

      final rawAlbums = _library.rawAlbums;
      final albumTitleById = <String, String>{};
      final albumArtistById = <String, String>{};
      final catalogAlbums = <CurationCatalogAlbum>[];
      for (final a in rawAlbums) {
        albumTitleById[a.id] = a.title;
        albumArtistById[a.id] = a.artist;
        catalogAlbums.add(
          CurationCatalogAlbum(
            id: a.id,
            title: a.title,
            artist: a.artist,
            songCount: a.songCount,
          ),
        );
      }

      final albumsSorted = List<AlbumModel>.from(rawAlbums)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      final songAlbumIdById = <String, String>{};
      final groupedSongs = <String, List<CurationCatalogSong>>{};
      final standalone = <CurationCatalogSong>[];
      for (final song in _library.rawSongs) {
        final albumId = song.albumId;
        if (albumId != null && albumId.trim().isNotEmpty) {
          songAlbumIdById[song.id] = albumId;
        }
        final mapped = _toCatalogSong(song, albumTitleById: albumTitleById);
        if (albumId == null || albumId.trim().isEmpty) {
          standalone.add(mapped);
        } else {
          groupedSongs
              .putIfAbsent(albumId, () => <CurationCatalogSong>[])
              .add(mapped);
        }
      }
      for (final tracks in groupedSongs.values) {
        tracks.sort(
          (a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0),
        );
      }

      final playlistAlbumIdsById = <String, List<String>>{};
      final playlistsSorted = _library.rawServerPlaylists
          .where((p) => !isAccountOwnedPlaylistId(p.id))
          .map((p) {
        final albumIds = <String>[];
        for (final songId in p.songIds) {
          final albumId = songAlbumIdById[songId];
          if (albumId != null && !albumIds.contains(albumId)) {
            albumIds.add(albumId);
            if (albumIds.length == 4) break;
          }
        }
        playlistAlbumIdsById[p.id] = albumIds;
        return CurationCatalogPlaylist(
          id: p.id,
          name: p.name,
          songCount: p.songCount,
        );
      }).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final allSongsSorted = List<SongModel>.from(_library.rawSongs)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      var curation = _curationService.curation;
      if (widget.initialModeOverride != null) {
        curation = curation.copyWith(mode: widget.initialModeOverride);
      }

      final draft = CurationDraft.fromCuration(curation);
      final groups = CurationDraft.buildArtistGroups(
        albums: catalogAlbums,
        standaloneSongs: standalone,
      );

      if (!mounted) return;
      setState(() {
        _draft = draft;
        _initialSnapshot = _snapshotFor(draft);
        _artistGroups = groups;
        _albumsSorted = albumsSorted;
        _playlistsSorted = playlistsSorted;
        _allSongsSorted = allSongsSorted;
        _songsByAlbum = groupedSongs;
        _albumArtistById = albumArtistById;
        _albumTitleById = albumTitleById;
        _playlistAlbumIdsById = playlistAlbumIdsById;
        _selectedArtistKey = groups.isNotEmpty ? groups.first.key : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load server catalog: $e';
      });
    }
  }

  CurationCatalogSong _toCatalogSong(
    SongModel s, {
    Map<String, String>? albumTitleById,
  }) {
    final titles = albumTitleById ?? _albumTitleById;
    return CurationCatalogSong(
      id: s.id,
      title: s.title,
      artist: s.artist,
      albumId: s.albumId,
      albumTitle: s.albumId == null ? null : titles[s.albumId!],
      durationSeconds: s.duration,
      trackNumber: s.trackNumber,
    );
  }

  String _snapshotFor(CurationDraft draft) {
    String joinSorted(Iterable<String> values) {
      final list = values.toList()..sort();
      return list.join('\u0000');
    }

    return [
      draft.mode.wireName,
      joinSorted(draft.includedArtists),
      joinSorted(draft.excludedArtists),
      joinSorted(draft.includedAlbums),
      joinSorted(draft.excludedAlbums),
      joinSorted(draft.includedSongs),
      joinSorted(draft.excludedSongs),
      joinSorted(draft.includedPlaylists),
      joinSorted(draft.excludedPlaylists),
    ].join('|');
  }

  bool get _hasUnsavedChanges {
    if (_isLoading || _error != null) return false;
    return _snapshotFor(_draft) != _initialSnapshot;
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved library curation changes. Leave without saving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _handleBackPressed() async {
    if (await _confirmDiscardIfNeeded()) {
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _curationService.saveCuration(
        mode: _draft.mode,
        rules: _draft.toRules(),
        onboardingCompleted: true,
      );
      if (!mounted) return;
      _initialSnapshot = _snapshotFor(_draft);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save library: $e')),
      );
    }
  }

  Future<void> _openModeSheet() async {
    final nextMode = await showCurationModeSheet(
      context,
      currentMode: _draft.mode,
    );
    if (!mounted || nextMode == null || nextMode == _draft.mode) return;
    setState(() => _draft.mode = nextMode);
  }

  String get _query => _searchController.text.trim().toLowerCase();

  bool _matchesStatus(bool included) {
    return switch (_statusFilter) {
      _CurationStatusFilter.all => true,
      _CurationStatusFilter.included => included,
      _CurationStatusFilter.excluded => !included,
    };
  }

  bool _isArtistIncludedForFilter(CurationArtistGroup group) {
    final state = _draft.artistCheckboxState(group);
    return state != CurationArtistSelectionState.none;
  }

  bool _isAlbumIncludedForFilter(AlbumModel album) {
    return _draft.filter.isAlbumIncluded(
      albumId: album.id,
      artist: album.artist,
    );
  }

  CurationArtistSelectionState _albumSelectionState(
    AlbumModel album,
    int includedTracks,
    int totalTracks,
  ) {
    final albumIncluded = _isAlbumIncludedForFilter(album);
    if (totalTracks == 0) {
      return albumIncluded
          ? CurationArtistSelectionState.all
          : CurationArtistSelectionState.none;
    }
    if (includedTracks == 0) return CurationArtistSelectionState.none;
    if (includedTracks == totalTracks && albumIncluded) {
      return CurationArtistSelectionState.all;
    }
    return CurationArtistSelectionState.partial;
  }

  int _includedTracksCount(AlbumModel album) {
    final tracks = _songsByAlbum[album.id];
    if (tracks == null || tracks.isEmpty) return 0;
    final filter = _draft.filter;
    var count = 0;
    for (final song in tracks) {
      if (filter.isSongIncluded(
        songId: song.id,
        artist: song.artist,
        albumId: album.id,
        albumArtist: album.artist,
      )) {
        count++;
      }
    }
    return count;
  }

  List<CurationArtistGroup> get _filteredArtists {
    final q = _query;
    return _artistGroups.where((g) {
      if (!_matchesStatus(_isArtistIncludedForFilter(g))) return false;
      if (q.isEmpty) return true;
      if (g.displayName.toLowerCase().contains(q)) return true;
      if (g.albums.any((a) => a.title.toLowerCase().contains(q))) return true;
      return g.standaloneSongs.any((s) => s.title.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  List<AlbumModel> get _filteredAlbums {
    final q = _query;
    return _albumsSorted.where((a) {
      if (!_matchesStatus(_isAlbumIncludedForFilter(a))) return false;
      if (q.isEmpty) return true;
      return a.title.toLowerCase().contains(q) ||
          a.artist.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  List<CurationCatalogPlaylist> get _filteredPlaylists {
    final q = _query;
    final filter = _draft.filter;
    return _playlistsSorted.where((p) {
      if (!_matchesStatus(filter.isServerPlaylistIncluded(p.id))) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  List<SongModel> get _filteredSongs {
    final rawQuery = _searchController.text.trim();
    final Iterable<SongModel> base;
    if (rawQuery.isEmpty) {
      base = _allSongsSorted;
    } else {
      final parsed = SearchQuery.parse(rawQuery);
      if (parsed.isEmpty) {
        base = _allSongsSorted;
      } else {
        base = LibrarySearchEngine.rank<SongModel>(
          parsed,
          _allSongsSorted,
          (s) => [
            SearchField(s.title, isPrimary: true),
            SearchField(s.artist),
            if (s.albumId != null && _albumTitleById[s.albumId!] != null)
              SearchField(_albumTitleById[s.albumId!]!),
          ],
          limit: 500,
        );
      }
    }
    if (_statusFilter == _CurationStatusFilter.all) {
      return base is List<SongModel> ? base : base.toList(growable: false);
    }
    final filter = _draft.filter;
    return base.where((song) {
      final albumArtist =
          song.albumId != null ? _albumArtistById[song.albumId!] : null;
      final included = filter.isSongIncluded(
        songId: song.id,
        artist: song.artist,
        albumId: song.albumId,
        albumArtist: albumArtist,
      );
      return _matchesStatus(included);
    }).toList(growable: false);
  }

  ({int count, bool allSelected}) _visibleBatchInfo() {
    switch (_tab) {
      case _CurateTab.artists:
        final items = _filteredArtists;
        final allSelected = items.isNotEmpty &&
            items.every(
              (g) =>
                  _draft.artistCheckboxState(g) ==
                  CurationArtistSelectionState.all,
            );
        return (count: items.length, allSelected: allSelected);
      case _CurateTab.albums:
        final items = _filteredAlbums;
        final allSelected =
            items.isNotEmpty && items.every(_isAlbumIncludedForFilter);
        return (count: items.length, allSelected: allSelected);
      case _CurateTab.playlists:
        final items = _filteredPlaylists;
        final filter = _draft.filter;
        final allSelected = items.isNotEmpty &&
            items.every((p) => filter.isServerPlaylistIncluded(p.id));
        return (count: items.length, allSelected: allSelected);
      case _CurateTab.songs:
        final items = _filteredSongs;
        final filter = _draft.filter;
        final allSelected = items.isNotEmpty &&
            items.every((s) {
              final albumArtist =
                  s.albumId != null ? _albumArtistById[s.albumId!] : null;
              return filter.isSongIncluded(
                songId: s.id,
                artist: s.artist,
                albumId: s.albumId,
                albumArtist: albumArtist,
              );
            });
        return (count: items.length, allSelected: allSelected);
    }
  }

  void _applyBatchToggle(bool select) {
    setState(() {
      switch (_tab) {
        case _CurateTab.artists:
          for (final g in _filteredArtists) {
            final state = _draft.artistCheckboxState(g);
            if (select && state != CurationArtistSelectionState.all) {
              _draft.toggleArtistWhole(g);
            } else if (!select && state != CurationArtistSelectionState.none) {
              if (state == CurationArtistSelectionState.partial) {
                _draft.toggleArtistWhole(g);
              }
              _draft.toggleArtistWhole(g);
            }
          }
        case _CurateTab.albums:
          for (final album in _filteredAlbums) {
            if (_isAlbumIncludedForFilter(album) != select) {
              _draft.toggleAlbum(
                CurationCatalogAlbum(
                  id: album.id,
                  title: album.title,
                  artist: album.artist,
                  songCount: album.songCount,
                ),
              );
            }
          }
        case _CurateTab.playlists:
          final filter = _draft.filter;
          for (final p in _filteredPlaylists) {
            if (filter.isServerPlaylistIncluded(p.id) != select) {
              _draft.togglePlaylist(p.id);
            }
          }
        case _CurateTab.songs:
          final filter = _draft.filter;
          for (final s in _filteredSongs) {
            final albumArtist =
                s.albumId != null ? _albumArtistById[s.albumId!] : null;
            final included = filter.isSongIncluded(
              songId: s.id,
              artist: s.artist,
              albumId: s.albumId,
              albumArtist: albumArtist,
            );
            if (included != select) {
              _draft.toggleSong(
                _toCatalogSong(s),
                albumArtist: albumArtist,
              );
            }
          }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleBackPressed());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: _handleBackPressed,
          ),
          titleSpacing: 0,
          title: Text(
            'Curate My Library',
            style: AppTheme.heading(20, color: colors.textPrimary),
          ),
          actions: _isLoading || _error != null
              ? null
              : [
                  _ModePillButton(
                    mode: _draft.mode,
                    onTap: _openModeSheet,
                  ),
                  PopupMenuButton<_OverflowMenuAction>(
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: colors.textPrimary,
                    ),
                    tooltip: 'Catalog actions',
                    onSelected: (action) {
                      setState(() {
                        switch (action) {
                          case _OverflowMenuAction.includeAll:
                            _draft.selectAll();
                          case _OverflowMenuAction.clearAll:
                            _draft.clearAll();
                        }
                      });
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _OverflowMenuAction.includeAll,
                        child: Text('Include entire catalog'),
                      ),
                      PopupMenuItem(
                        value: _OverflowMenuAction.clearAll,
                        child: Text('Clear all selections'),
                      ),
                    ],
                  ),
                ],
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: colors.groundGradient),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildErrorState(colors)
                  : Column(
                      children: [
                        _buildTabStrip(colors),
                        _buildSearchAndFilterBar(colors),
                        Expanded(
                          child: switch (_tab) {
                            _CurateTab.artists => _buildArtistsTab(),
                            _CurateTab.albums => _buildAlbumsTab(),
                            _CurateTab.playlists => _buildPlaylistsTab(),
                            _CurateTab.songs => _buildSongsTab(),
                          },
                        ),
                        _buildFooter(colors),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildErrorState(PlayerColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabStrip(PlayerColors colors) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorColor: colors.textPrimary,
        indicatorWeight: 2,
        labelColor: colors.textPrimary,
        unselectedLabelColor: colors.textSecondary,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        labelStyle: const TextStyle(
          fontFamily: AppTheme.bodyFamily,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          fontFeatures: AppTheme.tabular,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: AppTheme.bodyFamily,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          fontFeatures: AppTheme.tabular,
        ),
        tabs: [
          Tab(height: 40, text: 'Artists ${_artistGroups.length}'),
          Tab(height: 40, text: 'Albums ${_albumsSorted.length}'),
          Tab(height: 40, text: 'Playlists ${_playlistsSorted.length}'),
          Tab(height: 40, text: 'Songs ${_allSongsSorted.length}'),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar(PlayerColors colors) {
    final isCurated = _draft.mode == LibraryCurationMode.curated;
    final batch = _visibleBatchInfo();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              style: TextStyle(fontSize: 14, color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: switch (_tab) {
                  _CurateTab.artists => 'Search artists, albums, or singles...',
                  _CurateTab.albums => 'Search albums or artists...',
                  _CurateTab.playlists => 'Search server playlists...',
                  _CurateTab.songs => 'Search all server songs...',
                },
                hintStyle: TextStyle(fontSize: 13.5, color: colors.textSecondary),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: _searchController.clear,
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _StatusFilterPill(
                        label: 'All',
                        selected: _statusFilter == _CurationStatusFilter.all,
                        onTap: () => setState(
                          () => _statusFilter = _CurationStatusFilter.all,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusFilterPill(
                        label: isCurated ? 'Selected' : 'Included',
                        selected:
                            _statusFilter == _CurationStatusFilter.included,
                        onTap: () => setState(
                          () => _statusFilter = _CurationStatusFilter.included,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusFilterPill(
                        label: isCurated ? 'Not selected' : 'Excluded',
                        selected:
                            _statusFilter == _CurationStatusFilter.excluded,
                        onTap: () => setState(
                          () => _statusFilter = _CurationStatusFilter.excluded,
                        ),
                      ),
                    ],
                  ),
                ),
                if (batch.count > 0) ...[
                  const SizedBox(width: 8),
                  _BatchActionButton(
                    label: batch.allSelected
                        ? (isCurated
                            ? 'Deselect ${batch.count}'
                            : 'Exclude ${batch.count}')
                        : 'Select ${batch.count}',
                    onTap: () => _applyBatchToggle(!batch.allSelected),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(PlayerColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: colors.band,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                _buildSummaryLine(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.textSecondary,
                  fontFeatures: AppTheme.tabular,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.base,
                      ),
                    )
                  : const Text('Save Library'),
            ),
          ],
        ),
      ),
    );
  }

  String _buildSummaryLine() {
    final filter = _draft.filter;
    if (_draft.mode == LibraryCurationMode.full) {
      final excluded = _draft
          .toRules()
          .where((r) => r.action == CurationRuleAction.exclude)
          .length;
      return excluded == 0
          ? 'Include Everything · Full server catalog'
          : 'Include Everything · $excluded excluded';
    }
    var fullArtists = 0;
    for (final g in _artistGroups) {
      if (_draft.artistCheckboxState(g) == CurationArtistSelectionState.all) {
        fullArtists++;
      }
    }
    var selectedAlbums = 0;
    for (final entry in _albumArtistById.entries) {
      if (filter.isAlbumIncluded(albumId: entry.key, artist: entry.value)) {
        selectedAlbums++;
      }
    }
    final selectedPlaylists = _playlistsSorted
        .where((p) => filter.isServerPlaylistIncluded(p.id))
        .length;
    return '$fullArtists artists · $selectedAlbums albums · '
        '$selectedPlaylists playlists';
  }

  Widget _buildEmptyFilteredState(String emptyMessage) {
    final colors = context.colors;
    final hasActiveFilters =
        _query.isNotEmpty || _statusFilter != _CurationStatusFilter.all;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasActiveFilters ? 'No items match your current filters.' : emptyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            if (hasActiveFilters) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _statusFilter = _CurationStatusFilter.all);
                },
                child: const Text('Reset filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildArtistsTab() {
    final artists = _filteredArtists;
    if (artists.isEmpty) {
      return _buildEmptyFilteredState('No artists found on server.');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        if (!wide) {
          return AlphabetScrubberList<CurationArtistGroup>(
            items: artists,
            labelOf: (g) => g.displayName,
            itemExtent: kCurationRowHeight,
            showScrubber: _query.isEmpty && artists.length >= 12,
            showSectionHeaders: _query.isEmpty,
            itemBuilder: (context, group, _) => _buildArtistRow(
              group,
              isWide: false,
            ),
          );
        }

        final selectedGroup = artists
                .where((g) => g.key == _selectedArtistKey)
                .firstOrNull ??
            artists.first;
        return Row(
          children: [
            SizedBox(
              width: 300,
              child: AlphabetScrubberList<CurationArtistGroup>(
                items: artists,
                labelOf: (g) => g.displayName,
                itemExtent: kCurationRowHeight,
                showScrubber: _query.isEmpty && artists.length >= 12,
                showSectionHeaders: _query.isEmpty,
                itemBuilder: (context, group, _) => _buildArtistRow(
                  group,
                  isWide: true,
                  selected: group.key == selectedGroup.key,
                ),
              ),
            ),
            VerticalDivider(width: 1, color: context.colors.border),
            Expanded(
              child: ArtistCurationDetailPane(
                group: selectedGroup,
                draft: _draft,
                songsByAlbum: _songsByAlbum,
                onChanged: () => setState(() {}),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArtistRow(
    CurationArtistGroup group, {
    required bool isWide,
    bool selected = false,
  }) {
    return CurationArtistTile(
      group: group,
      selectionState: _draft.artistCheckboxState(group),
      includedCount: _draft.includedItemCountForArtist(group),
      isWideSelected: selected,
      showChevron: !isWide,
      onToggleWhole: () => setState(() => _draft.toggleArtistWhole(group)),
      onTap: () {
        if (isWide) {
          setState(() => _selectedArtistKey = group.key);
        } else {
          _openArtistSheet(group);
        }
      },
    );
  }

  Future<void> _openArtistSheet(CurationArtistGroup group) async {
    await showAriamiSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      header: AriamiSheetHeader(
        title: group.displayName,
        leading: CurationArtistArtwork(
          artistName: group.displayName,
          fallbackAlbum: group.albums.firstOrNull,
          size: 36,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return ArtistCurationDetailPane(
              group: group,
              draft: _draft,
              songsByAlbum: _songsByAlbum,
              onChanged: () {
                setSheetState(() {});
                if (mounted) setState(() {});
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildAlbumsTab() {
    final albums = _filteredAlbums;
    if (albums.isEmpty) {
      return _buildEmptyFilteredState('No albums found on server.');
    }

    return AlphabetScrubberList<AlbumModel>(
      items: albums,
      labelOf: (a) => a.title,
      itemExtent: kCurationRowHeight,
      showScrubber: _query.isEmpty && albums.length >= 12,
      showSectionHeaders: _query.isEmpty,
      itemBuilder: (context, album, _) {
        final tracks = _songsByAlbum[album.id] ?? const <CurationCatalogSong>[];
        final includedTracks = _includedTracksCount(album);
        return CurationAlbumTile(
          album: album,
          selectionState: _albumSelectionState(
            album,
            includedTracks,
            tracks.length,
          ),
          includedTrackCount: includedTracks,
          totalTrackCount: tracks.length,
          onToggle: () => setState(() {
            _draft.toggleAlbum(
              CurationCatalogAlbum(
                id: album.id,
                title: album.title,
                artist: album.artist,
                songCount: album.songCount,
              ),
            );
          }),
          onOpenTracks: tracks.isEmpty
              ? null
              : () => showAlbumTracksCurationSheet(
                    context,
                    album: album,
                    tracks: tracks,
                    draft: _draft,
                    onChanged: () {
                      if (mounted) setState(() {});
                    },
                  ),
        );
      },
    );
  }

  Widget _buildPlaylistsTab() {
    final items = _filteredPlaylists;
    if (items.isEmpty) {
      return _buildEmptyFilteredState('No server playlists found.');
    }
    final filter = _draft.filter;
    return AlphabetScrubberList<CurationCatalogPlaylist>(
      items: items,
      labelOf: (p) => p.name,
      itemExtent: kCurationRowHeight,
      showScrubber: _query.isEmpty && items.length >= 12,
      showSectionHeaders: false,
      itemBuilder: (context, playlist, _) {
        final included = filter.isServerPlaylistIncluded(playlist.id);
        return CurationPlaylistTile(
          playlist: playlist,
          albumIds: _playlistAlbumIdsById[playlist.id] ?? const <String>[],
          included: included,
          onToggle: () => setState(() => _draft.togglePlaylist(playlist.id)),
        );
      },
    );
  }

  Widget _buildSongsTab() {
    final items = _filteredSongs;
    if (items.isEmpty) {
      return _buildEmptyFilteredState('No songs found on server.');
    }
    final filter = _draft.filter;
    return AlphabetScrubberList<SongModel>(
      items: items,
      labelOf: (s) => s.title,
      itemExtent: kCurationRowHeight,
      showScrubber: _query.isEmpty && items.length >= 12,
      showSectionHeaders: _query.isEmpty,
      itemBuilder: (context, song, _) {
        final albumArtist =
            song.albumId != null ? _albumArtistById[song.albumId!] : null;
        final included = filter.isSongIncluded(
          songId: song.id,
          artist: song.artist,
          albumId: song.albumId,
          albumArtist: albumArtist,
        );
        return CurationSongTile(
          song: song,
          albumTitle: song.albumId != null ? _albumTitleById[song.albumId!] : null,
          included: included,
          onToggle: () => setState(() {
            _draft.toggleSong(
              _toCatalogSong(song),
              albumArtist: albumArtist,
            );
          }),
        );
      },
    );
  }
}

class _ModePillButton extends StatelessWidget {
  const _ModePillButton({
    required this.mode,
    required this.onTap,
  });

  final LibraryCurationMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isFull = mode == LibraryCurationMode.full;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.tileRadius),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.tileRadius),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isFull ? Icons.all_inclusive_rounded : Icons.tune_rounded,
                  size: 14,
                  color: colors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  isFull ? 'Include All' : 'Curated',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusFilterPill extends StatelessWidget {
  const _StatusFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.textPrimary : colors.surfaceHigh,
      borderRadius: BorderRadius.circular(AppTheme.tileRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.tileRadius),
            border: Border.all(
              color: selected ? colors.textPrimary : colors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? colors.base : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchActionButton extends StatelessWidget {
  const _BatchActionButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.tileRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.tileRadius),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
              fontFeatures: AppTheme.tabular,
            ),
          ),
        ),
      ),
    );
  }
}
