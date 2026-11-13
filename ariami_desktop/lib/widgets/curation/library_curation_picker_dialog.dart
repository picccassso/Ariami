import 'dart:async';

import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:ariami_core/services/search/search.dart';
import 'package:ariami_core/services/stats/credited_artist_splitter.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import 'alphabet_scrubber.dart';
import 'artist_detail_pane.dart';
import 'curation_rows.dart';

typedef CurationSaveCallback = Future<UserLibraryCuration?> Function(
  LibraryCurationMode mode,
  List<CurationRuleEntry> rules,
);

typedef CurationAlbumSongsLoader = Future<List<CurationCatalogSong>> Function(
  String albumId,
);

typedef CurationSongsSearchCallback = Future<List<CurationCatalogSong>> Function(
  String query,
);

typedef CurationCatalogBundle = ({
  UserLibraryCuration curation,
  List<CurationCatalogAlbum> albums,
  List<CurationCatalogPlaylist> playlists,
  List<CurationCatalogSong> standaloneSongs,
});

/// Shared curation picker dialog for the Desktop Server Dashboard
/// (admin curating any account).
Future<UserLibraryCuration?> showLibraryCurationPickerDialog(
  BuildContext context, {
  required String title,
  required Future<CurationCatalogBundle> Function() loadBundle,
  required CurationSaveCallback onSave,
  CurationAlbumSongsLoader? loadAlbumSongs,
  CurationSongsSearchCallback? searchAllSongs,
  LibraryCurationMode? initialModeOverride,
  FutureOr<List<CurationCatalogSong>> Function()? loadAllSongs,
  Map<String, List<String>> Function()? loadPlaylistAlbumIds,
  CurationArtworkClient? artworkClient,
  int? Function(String artistName)? artistImageVersionOf,
  int? Function(String playlistId)? playlistImageVersionOf,
}) {
  return showDialog<UserLibraryCuration>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _LibraryCurationPickerDialog(
      title: title,
      loadBundle: loadBundle,
      onSave: onSave,
      loadAlbumSongs: loadAlbumSongs,
      searchAllSongs: searchAllSongs,
      initialModeOverride: initialModeOverride,
      loadAllSongs: loadAllSongs,
      loadPlaylistAlbumIds: loadPlaylistAlbumIds,
      artworkClient: artworkClient,
      artistImageVersionOf: artistImageVersionOf,
      playlistImageVersionOf: playlistImageVersionOf,
    ),
  );
}

enum _PickerTab {
  artists,
  albums,
  playlists,
  songs,
}

enum _CurationStatusFilter { all, included, excluded }

enum _OverflowMenuAction { includeAll, clearAll }

class _LibraryCurationPickerDialog extends StatefulWidget {
  const _LibraryCurationPickerDialog({
    required this.title,
    required this.loadBundle,
    required this.onSave,
    this.loadAlbumSongs,
    this.searchAllSongs,
    this.initialModeOverride,
    this.loadAllSongs,
    this.loadPlaylistAlbumIds,
    this.artworkClient,
    this.artistImageVersionOf,
    this.playlistImageVersionOf,
  });

  final String title;
  final Future<CurationCatalogBundle> Function() loadBundle;
  final CurationSaveCallback onSave;
  final CurationAlbumSongsLoader? loadAlbumSongs;
  final CurationSongsSearchCallback? searchAllSongs;
  final LibraryCurationMode? initialModeOverride;
  final FutureOr<List<CurationCatalogSong>> Function()? loadAllSongs;
  final Map<String, List<String>> Function()? loadPlaylistAlbumIds;
  final CurationArtworkClient? artworkClient;
  final int? Function(String artistName)? artistImageVersionOf;
  final int? Function(String playlistId)? playlistImageVersionOf;

  @override
  State<_LibraryCurationPickerDialog> createState() =>
      _LibraryCurationPickerDialogState();
}

class _LibraryCurationPickerDialogState
    extends State<_LibraryCurationPickerDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  late CurationDraft _draft;
  String _initialSnapshot = '';

  List<CurationArtistGroup> _artistGroups = const <CurationArtistGroup>[];
  List<CurationCatalogAlbum> _albumsSorted = const <CurationCatalogAlbum>[];
  List<CurationCatalogPlaylist> _playlistsSorted =
      const <CurationCatalogPlaylist>[];
  List<CurationCatalogSong> _allSongsSorted = const <CurationCatalogSong>[];

  final Map<String, List<CurationCatalogSong>> _songsByAlbum =
      <String, List<CurationCatalogSong>>{};
  Map<String, String> _albumArtistById = const <String, String>{};
  Map<String, String> _albumTitleById = const <String, String>{};
  Map<String, List<String>> _playlistAlbumIdsById =
      const <String, List<String>>{};
  Map<String, String> _artistFallbackAlbumIdByKey = const <String, String>{};
  Map<String, String> _artistFallbackSongIdByKey = const <String, String>{};

  List<CurationCatalogSong>? _searchedSongs;
  bool _isSearchingSongs = false;
  Timer? _songSearchDebounce;
  bool _hasLoadedAllSongs = false;

  _PickerTab _tab = _PickerTab.artists;
  _CurationStatusFilter _statusFilter = _CurationStatusFilter.all;
  String? _selectedArtistKey;

  @override
  void initState() {
    super.initState();
    _draft = CurationDraft(
      mode: widget.initialModeOverride ?? LibraryCurationMode.full,
    );
    _tabController = TabController(length: _PickerTab.values.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _searchController.addListener(_onSearchChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _songSearchDebounce?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final nextTab = _PickerTab.values[_tabController.index];
    if (nextTab != _tab) {
      setState(() => _tab = nextTab);
      if (nextTab == _PickerTab.songs && !_hasLoadedAllSongs) {
        _scheduleSongSearch();
      }
    }
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {});
    if (_tab == _PickerTab.songs && !_hasLoadedAllSongs) {
      _scheduleSongSearch();
    }
  }

  void _scheduleSongSearch() {
    _songSearchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty || widget.searchAllSongs == null) {
      setState(() {
        _searchedSongs = null;
        _isSearchingSongs = false;
      });
      return;
    }
    _songSearchDebounce = Timer(const Duration(milliseconds: 220), () async {
      setState(() => _isSearchingSongs = true);
      try {
        final songs = await widget.searchAllSongs!(query);
        if (!mounted || _searchController.text.trim() != query) return;
        setState(() {
          _searchedSongs = songs;
          _isSearchingSongs = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSearchingSongs = false);
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final bundle = await widget.loadBundle();
      if (!mounted) return;

      final loadedAllSongs = widget.loadAllSongs != null
          ? await widget.loadAllSongs!()
          : null;
      if (!mounted) return;

      final albumTitleById = <String, String>{};
      final albumArtistById = <String, String>{};
      for (final a in bundle.albums) {
        albumTitleById[a.id] = a.title;
        albumArtistById[a.id] = a.artist;
      }

      final albumsSorted = List<CurationCatalogAlbum>.from(bundle.albums)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      final playlistsSorted =
          List<CurationCatalogPlaylist>.from(bundle.playlists)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      final hasAllSongs = loadedAllSongs != null;
      final sourceSongs = loadedAllSongs ?? bundle.standaloneSongs;
      final allSongsSorted = sourceSongs
          .map(
            (s) => s.albumTitle != null || s.albumId == null
                ? s
                : CurationCatalogSong(
                    id: s.id,
                    title: s.title,
                    artist: s.artist,
                    albumId: s.albumId,
                    albumTitle: albumTitleById[s.albumId!],
                    durationSeconds: s.durationSeconds,
                    trackNumber: s.trackNumber,
                  ),
          )
          .toList()
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      final groupedSongs = <String, List<CurationCatalogSong>>{};
      for (final song in allSongsSorted) {
        final albumId = song.albumId;
        if (albumId != null && albumId.trim().isNotEmpty) {
          groupedSongs
              .putIfAbsent(albumId, () => <CurationCatalogSong>[])
              .add(song);
        }
      }
      for (final tracks in groupedSongs.values) {
        tracks.sort(
          (a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0),
        );
      }

      final groups = CurationDraft.buildArtistGroups(
        albums: bundle.albums,
        standaloneSongs: bundle.standaloneSongs,
      );

      final splitter = CreditedArtistSplitter();
      final songIdByArtistKey = <String, String>{};
      final songAlbumIdByArtistKey = <String, String>{};
      void indexSongArtist(String key, CurationCatalogSong song) {
        if (key.isEmpty) return;
        songIdByArtistKey.putIfAbsent(key, () => song.id);
        final albumId = song.albumId?.trim();
        if (albumId != null && albumId.isNotEmpty) {
          songAlbumIdByArtistKey.putIfAbsent(key, () => albumId);
        }
      }

      for (final song in allSongsSorted) {
        indexSongArtist(normalizeArtistKey(song.artist), song);
        for (final credit in splitter.split(song.artist)) {
          indexSongArtist(credit.key, song);
        }
      }

      final fallbackAlbumIdByKey = <String, String>{};
      final fallbackSongIdByKey = <String, String>{};
      for (final group in groups) {
        String? albumId = group.albums.firstOrNull?.id;
        albumId ??= songAlbumIdByArtistKey[group.key];
        if (albumId != null && albumId.isNotEmpty) {
          fallbackAlbumIdByKey[group.key] = albumId;
        }

        String? songId = group.standaloneSongs.firstOrNull?.id;
        if (songId == null) {
          for (final album in group.albums) {
            final firstTrackId = groupedSongs[album.id]?.firstOrNull?.id;
            if (firstTrackId != null && firstTrackId.isNotEmpty) {
              songId = firstTrackId;
              break;
            }
          }
        }
        songId ??= songIdByArtistKey[group.key];
        if (songId != null && songId.isNotEmpty) {
          fallbackSongIdByKey[group.key] = songId;
        }
      }

      final draft = CurationDraft.fromCuration(bundle.curation);
      if (widget.initialModeOverride != null) {
        draft.mode = widget.initialModeOverride!;
      }

      final playlistAlbumIds =
          widget.loadPlaylistAlbumIds?.call() ?? const <String, List<String>>{};

      setState(() {
        _draft = draft;
        _initialSnapshot = _snapshotFor(draft);
        _artistGroups = groups;
        _albumsSorted = albumsSorted;
        _playlistsSorted = playlistsSorted;
        _allSongsSorted = allSongsSorted;
        _hasLoadedAllSongs = hasAllSongs;
        _songsByAlbum
          ..clear()
          ..addAll(groupedSongs);
        _albumArtistById = albumArtistById;
        _albumTitleById = albumTitleById;
        _playlistAlbumIdsById = playlistAlbumIds;
        _artistFallbackAlbumIdByKey = fallbackAlbumIdByKey;
        _artistFallbackSongIdByKey = fallbackSongIdByKey;
        _selectedArtistKey = groups.isNotEmpty ? groups.first.key : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load catalog ($e).';
        _isLoading = false;
      });
    }
  }

  Future<List<CurationCatalogSong>> _requestAlbumTracks(String albumId) async {
    final existing = _songsByAlbum[albumId];
    if (existing != null) return existing;
    final loader = widget.loadAlbumSongs;
    if (loader == null) return const <CurationCatalogSong>[];
    final loaded = await loader(albumId);
    final sorted = List<CurationCatalogSong>.from(loaded)
      ..sort((a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0));
    if (mounted) {
      setState(() {
        _songsByAlbum[albumId] = sorted;
      });
    } else {
      _songsByAlbum[albumId] = sorted;
    }
    return sorted;
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
        backgroundColor: AppColors.popover,
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

  Future<void> _handleClosePressed() async {
    if (await _confirmDiscardIfNeeded()) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(_draft.mode, _draft.toRules());
      if (!mounted) return;
      _initialSnapshot = _snapshotFor(_draft);
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to save curation ($e).';
        _isSaving = false;
      });
    }
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

  bool _isAlbumIncludedForFilter(CurationCatalogAlbum album) {
    return _draft.filter.isAlbumIncluded(
      albumId: album.id,
      artist: album.artist,
    );
  }

  CurationArtistSelectionState _albumSelectionState(
    CurationCatalogAlbum album,
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

  int _includedTracksCount(CurationCatalogAlbum album) {
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

  List<CurationCatalogAlbum> get _filteredAlbums {
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

  List<CurationCatalogSong> get _filteredSongs {
    final rawQuery = _searchController.text.trim();
    final Iterable<CurationCatalogSong> base;
    if (rawQuery.isEmpty) {
      base = _allSongsSorted;
    } else if (!_hasLoadedAllSongs && _searchedSongs != null) {
      base = _searchedSongs!;
    } else {
      final parsed = SearchQuery.parse(rawQuery);
      if (parsed.isEmpty) {
        base = _allSongsSorted;
      } else {
        base = LibrarySearchEngine.rank<CurationCatalogSong>(
          parsed,
          _allSongsSorted,
          (s) {
            final albumTitle = s.albumTitle ??
                (s.albumId != null ? _albumTitleById[s.albumId!] : null);
            return [
              SearchField(s.title, isPrimary: true),
              SearchField(s.artist),
              if (albumTitle != null) SearchField(albumTitle),
            ];
          },
          limit: 500,
        );
      }
    }
    if (_statusFilter == _CurationStatusFilter.all) {
      return base is List<CurationCatalogSong>
          ? base
          : base.toList(growable: false);
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
      case _PickerTab.artists:
        final items = _filteredArtists;
        final allSelected = items.isNotEmpty &&
            items.every(
              (g) =>
                  _draft.artistCheckboxState(g) ==
                  CurationArtistSelectionState.all,
            );
        return (count: items.length, allSelected: allSelected);
      case _PickerTab.albums:
        final items = _filteredAlbums;
        final allSelected =
            items.isNotEmpty && items.every(_isAlbumIncludedForFilter);
        return (count: items.length, allSelected: allSelected);
      case _PickerTab.playlists:
        final items = _filteredPlaylists;
        final filter = _draft.filter;
        final allSelected = items.isNotEmpty &&
            items.every((p) => filter.isServerPlaylistIncluded(p.id));
        return (count: items.length, allSelected: allSelected);
      case _PickerTab.songs:
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
        case _PickerTab.artists:
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
        case _PickerTab.albums:
          for (final album in _filteredAlbums) {
            if (_isAlbumIncludedForFilter(album) != select) {
              _draft.toggleAlbum(album);
            }
          }
        case _PickerTab.playlists:
          final filter = _draft.filter;
          for (final p in _filteredPlaylists) {
            if (filter.isServerPlaylistIncluded(p.id) != select) {
              _draft.togglePlaylist(p.id);
            }
          }
        case _PickerTab.songs:
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
              _draft.toggleSong(s, albumArtist: albumArtist);
            }
          }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 48).clamp(360.0, 980.0);
    final height = (screen.height - 64).clamp(440.0, 740.0);

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleClosePressed());
        }
      },
      child: Dialog(
        backgroundColor: AppColors.popover,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const Divider(height: 1, color: AppColors.border),
              if (!_isLoading && _error == null) ...[
                _buildTabStrip(),
                _buildSearchAndFilterBar(),
                const Divider(height: 1, color: AppColors.border),
              ],
              Expanded(child: _buildBody(width)),
              const Divider(height: 1, color: AppColors.border),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: AppTheme.heading(20, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 3),
              Text(
                _draft.mode == LibraryCurationMode.full
                    ? 'Include Everything — new scans appear automatically unless excluded.'
                    : 'Curated Mode — only selected artists, albums, playlists, and songs appear.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isLoading && _error == null) ...[
                SegmentedButton<LibraryCurationMode>(
                  segments: const [
                    ButtonSegment(
                      value: LibraryCurationMode.full,
                      label: Text('Include Everything'),
                    ),
                    ButtonSegment(
                      value: LibraryCurationMode.curated,
                      label: Text('Curated Mode'),
                    ),
                  ],
                  selected: <LibraryCurationMode>{_draft.mode},
                  onSelectionChanged: (selection) {
                    setState(() => _draft.mode = selection.first);
                  },
                ),
                const SizedBox(width: 4),
                PopupMenuButton<_OverflowMenuAction>(
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: AppColors.textPrimary,
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
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 19),
                tooltip: 'Close',
                onPressed: _isSaving ? null : _handleClosePressed,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabStrip() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorColor: AppColors.textPrimary,
        indicatorWeight: 2,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
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

  Widget _buildSearchAndFilterBar() {
    final isCurated = _draft.mode == LibraryCurationMode.curated;
    final batch = _visibleBatchInfo();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: switch (_tab) {
                    _PickerTab.artists =>
                      'Search artists, albums, or singles...',
                    _PickerTab.albums => 'Search albums or artists...',
                    _PickerTab.playlists => 'Search server playlists...',
                    _PickerTab.songs => 'Search all server songs...',
                  },
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 17),
                          tooltip: 'Clear filter',
                          onPressed: _searchController.clear,
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surfaceHigh,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.tileRadius),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.tileRadius),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.tileRadius),
                    borderSide: const BorderSide(color: AppColors.textPrimary),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 30,
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                  selected: _statusFilter == _CurationStatusFilter.included,
                  onTap: () => setState(
                    () => _statusFilter = _CurationStatusFilter.included,
                  ),
                ),
                const SizedBox(width: 6),
                _StatusFilterPill(
                  label: isCurated ? 'Not selected' : 'Excluded',
                  selected: _statusFilter == _CurationStatusFilter.excluded,
                  onTap: () => setState(
                    () => _statusFilter = _CurationStatusFilter.excluded,
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

  Widget _buildBody(double width) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return switch (_tab) {
      _PickerTab.artists => _buildArtistsTab(width),
      _PickerTab.albums => _buildAlbumsTab(),
      _PickerTab.playlists => _buildPlaylistsTab(),
      _PickerTab.songs => _buildSongsTab(),
    };
  }

  Widget _buildEmptyFilteredState(String emptyMessage) {
    final hasActiveFilters =
        _query.isNotEmpty || _statusFilter != _CurationStatusFilter.all;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasActiveFilters
                  ? 'No items match your current filters.'
                  : emptyMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
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

  Widget _buildArtistsTab(double width) {
    final artists = _filteredArtists;
    if (artists.isEmpty) {
      return _buildEmptyFilteredState('No artists found on server.');
    }

    final wide = width >= 600;
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
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
        const VerticalDivider(width: 1, color: AppColors.border),
        Expanded(
          child: ArtistCurationDetailPane(
            group: selectedGroup,
            draft: _draft,
            songsByAlbum: _songsByAlbum,
            artworkClient: widget.artworkClient,
            artistImageVersion:
                widget.artistImageVersionOf?.call(selectedGroup.displayName),
            fallbackAlbumId: _artistFallbackAlbumIdByKey[selectedGroup.key],
            fallbackSongId: _artistFallbackSongIdByKey[selectedGroup.key],
            onRequestAlbumTracks:
                widget.loadAlbumSongs != null ? _requestAlbumTracks : null,
            onChanged: () => setState(() {}),
          ),
        ),
      ],
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
      artworkClient: widget.artworkClient,
      customImageVersion: widget.artistImageVersionOf?.call(group.displayName),
      fallbackAlbumId: _artistFallbackAlbumIdByKey[group.key],
      fallbackSongId: _artistFallbackSongIdByKey[group.key],
      isWideSelected: selected,
      showChevron: !isWide,
      onToggleWhole: () => setState(() => _draft.toggleArtistWhole(group)),
      onTap: () {
        if (isWide) {
          setState(() => _selectedArtistKey = group.key);
        } else {
          unawaited(_openArtistDialog(group));
        }
      },
    );
  }

  Future<void> _openArtistDialog(CurationArtistGroup group) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.popover,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
          child: StatefulBuilder(
            builder: (innerContext, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ArtistCurationDetailPane(
                      group: group,
                      draft: _draft,
                      songsByAlbum: _songsByAlbum,
                      artworkClient: widget.artworkClient,
                      artistImageVersion:
                          widget.artistImageVersionOf?.call(group.displayName),
                      fallbackAlbumId: _artistFallbackAlbumIdByKey[group.key],
                      fallbackSongId: _artistFallbackSongIdByKey[group.key],
                      shrinkWrap: true,
                      onRequestAlbumTracks: widget.loadAlbumSongs != null
                          ? _requestAlbumTracks
                          : null,
                      onChanged: () {
                        setDialogState(() {});
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumsTab() {
    final albums = _filteredAlbums;
    if (albums.isEmpty) {
      return _buildEmptyFilteredState('No albums found on server.');
    }

    return AlphabetScrubberList<CurationCatalogAlbum>(
      items: albums,
      labelOf: (a) => a.title,
      itemExtent: kCurationRowHeight,
      showScrubber: _query.isEmpty && albums.length >= 12,
      showSectionHeaders: _query.isEmpty,
      itemBuilder: (context, album, _) {
        final tracks = _songsByAlbum[album.id] ?? const <CurationCatalogSong>[];
        final includedTracks = _includedTracksCount(album);
        final canPickTracks =
            tracks.isNotEmpty || widget.loadAlbumSongs != null;
        return CurationAlbumTile(
          album: album,
          selectionState: _albumSelectionState(
            album,
            includedTracks,
            tracks.length,
          ),
          includedTrackCount: includedTracks,
          totalTrackCount: tracks.length,
          artworkClient: widget.artworkClient,
          onToggle: () => setState(() => _draft.toggleAlbum(album)),
          onOpenTracks: !canPickTracks
              ? null
              : () => showAlbumTracksCurationDialog(
                    context,
                    album: album,
                    initialTracks: tracks,
                    draft: _draft,
                    artworkClient: widget.artworkClient,
                    onRequestTracks: widget.loadAlbumSongs != null
                        ? _requestAlbumTracks
                        : null,
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
          artworkClient: widget.artworkClient,
          customImageVersion:
              widget.playlistImageVersionOf?.call(playlist.id),
          onToggle: () => setState(() => _draft.togglePlaylist(playlist.id)),
        );
      },
    );
  }

  Widget _buildSongsTab() {
    if (_isSearchingSongs) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _filteredSongs;
    if (items.isEmpty) {
      return _buildEmptyFilteredState('No songs found on server.');
    }
    final filter = _draft.filter;
    return AlphabetScrubberList<CurationCatalogSong>(
      items: items,
      labelOf: (s) => s.title,
      itemExtent: kCurationRowHeight,
      showScrubber: _query.isEmpty && items.length >= 12,
      showSectionHeaders: _query.isEmpty,
      itemBuilder: (context, song, _) {
        final albumArtist =
            song.albumId != null ? _albumArtistById[song.albumId!] : null;
        final albumTitle = song.albumTitle ??
            (song.albumId != null ? _albumTitleById[song.albumId!] : null);
        final included = filter.isSongIncluded(
          songId: song.id,
          artist: song.artist,
          albumId: song.albumId,
          albumArtist: albumArtist,
        );
        return CurationSongTile(
          song: song,
          albumTitle: albumTitle,
          included: included,
          artworkClient: widget.artworkClient,
          onToggle: () => setState(
            () => _draft.toggleSong(song, albumArtist: albumArtist),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _buildSummaryLine(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                fontFeatures: AppTheme.tabular,
              ),
            ),
          ),
          TextButton(
            onPressed: _isSaving ? null : _handleClosePressed,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _isLoading || _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.base,
                    ),
                  )
                : const Text('Save Library'),
          ),
        ],
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
    return Material(
      color: selected ? AppColors.textPrimary : AppColors.surfaceHigh,
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
              color: selected ? AppColors.textPrimary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.base : AppColors.textPrimary,
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
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontFeatures: AppTheme.tabular,
            ),
          ),
        ),
      ),
    );
  }
}
