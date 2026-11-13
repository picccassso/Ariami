import 'dart:async';

import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:ariami_core/services/playlists/created_playlist_id.dart';
import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../services/curation/library_curation_service.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../main/library/library_controller.dart';

/// Shows the one-time first-sign-in curation prompt for non-owner users.
Future<void> showMobileCurationOnboardingSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.library_music_rounded,
                color: Theme.of(sheetContext).colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Set Up Your Library',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Choose how your personal library starts on this server. You can '
            'change this anytime from Library Options or Settings.',
            style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
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
    ),
  );

  if (!context.mounted) return;
  if (choice == 'full') {
    try {
      await LibraryCurationService().completeOnboardingFull();
    } catch (_) {}
  } else if (choice == 'curate') {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CurateLibraryScreen(
          initialModeOverride: LibraryCurationMode.curated,
        ),
      ),
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.primary, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CurateTab { artists, playlists, songs }

class CurateLibraryScreen extends StatefulWidget {
  const CurateLibraryScreen({
    super.key,
    this.initialModeOverride,
  });

  final LibraryCurationMode? initialModeOverride;

  @override
  State<CurateLibraryScreen> createState() => _CurateLibraryScreenState();
}

class _CurateLibraryScreenState extends State<CurateLibraryScreen> {
  final LibraryController _library = LibraryController();
  final LibraryCurationService _curationService = LibraryCurationService();
  final TextEditingController _searchController = TextEditingController();

  late CurationDraft _draft;
  List<CurationArtistGroup> _artistGroups = const <CurationArtistGroup>[];
  List<CurationCatalogPlaylist> _playlists = const <CurationCatalogPlaylist>[];
  List<CurationCatalogSong> _standaloneSongs = const <CurationCatalogSong>[];
  Map<String, List<CurationCatalogSong>> _songsByAlbum = const {};
  Map<String, String> _albumArtistById = const {};

  _CurateTab _tab = _CurateTab.artists;
  String? _selectedArtistKey;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

      final albums = _library.rawAlbums
          .map(
            (a) => CurationCatalogAlbum(
              id: a.id,
              title: a.title,
              artist: a.artist,
              songCount: a.songCount,
            ),
          )
          .toList(growable: false);
      final playlists = _library.rawServerPlaylists
          .where((p) => !isAccountOwnedPlaylistId(p.id))
          .map(
            (p) => CurationCatalogPlaylist(
              id: p.id,
              name: p.name,
              songCount: p.songCount,
            ),
          )
          .toList(growable: false);

      final groupedSongs = <String, List<CurationCatalogSong>>{};
      final standalone = <CurationCatalogSong>[];
      for (final song in _library.rawSongs) {
        final mapped = _toCatalogSong(song);
        final albumId = song.albumId;
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

      var curation = _curationService.curation;
      if (widget.initialModeOverride != null) {
        curation = curation.copyWith(mode: widget.initialModeOverride);
      }

      final draft = CurationDraft.fromCuration(curation);
      final groups = CurationDraft.buildArtistGroups(
        albums: albums,
        standaloneSongs: standalone,
      );

      if (!mounted) return;
      setState(() {
        _draft = draft;
        _artistGroups = groups;
        _playlists = playlists;
        _standaloneSongs = standalone;
        _songsByAlbum = groupedSongs;
        _albumArtistById = {for (final a in albums) a.id: a.artist};
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

  CurationCatalogSong _toCatalogSong(SongModel s) => CurationCatalogSong(
        id: s.id,
        title: s.title,
        artist: s.artist,
        albumId: s.albumId,
        albumTitle: s.albumId == null
            ? null
            : _library.rawAlbums
                .where((a) => a.id == s.albumId)
                .map((a) => a.title)
                .firstOrNull,
        durationSeconds: s.duration,
        trackNumber: s.trackNumber,
      );

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
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save library: $e')),
      );
    }
  }

  String get _query => _searchController.text.trim().toLowerCase();

  List<CurationArtistGroup> get _filteredArtists {
    final q = _query;
    if (q.isEmpty) return _artistGroups;
    return _artistGroups.where((g) {
      if (g.displayName.toLowerCase().contains(q)) return true;
      if (g.albums.any((a) => a.title.toLowerCase().contains(q))) return true;
      return g.standaloneSongs.any((s) => s.title.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  List<CurationCatalogPlaylist> get _filteredPlaylists {
    final q = _query;
    if (q.isEmpty) return _playlists;
    return _playlists
        .where((p) => p.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  List<CurationCatalogSong> get _filteredSongs {
    final q = _query;
    if (q.isEmpty) return _standaloneSongs;
    return _library.rawSongs
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q),
        )
        .take(100)
        .map(_toCatalogSong)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Curate My Library'),
        actions: [
          if (!_isLoading && _error == null)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<LibraryCurationMode>(
                            segments: const [
                              ButtonSegment(
                                value: LibraryCurationMode.full,
                                icon: Icon(Icons.all_inclusive_rounded),
                                label: Text('Include Everything'),
                              ),
                              ButtonSegment(
                                value: LibraryCurationMode.curated,
                                icon: Icon(Icons.tune_rounded),
                                label: Text('Curated Mode'),
                              ),
                            ],
                            selected: <LibraryCurationMode>{_draft.mode},
                            onSelectionChanged: (selection) {
                              setState(() {
                                _draft.mode = selection.first;
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<_CurateTab>(
                            segments: [
                              ButtonSegment(
                                value: _CurateTab.artists,
                                label: Text('Artists (${_artistGroups.length})'),
                              ),
                              ButtonSegment(
                                value: _CurateTab.playlists,
                                label: Text('Playlists (${_playlists.length})'),
                              ),
                              const ButtonSegment(
                                value: _CurateTab.songs,
                                label: Text('Songs'),
                              ),
                            ],
                            selected: <_CurateTab>{_tab},
                            onSelectionChanged: (selection) {
                              setState(() => _tab = selection.first);
                            },
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: switch (_tab) {
                                _CurateTab.artists =>
                                  'Filter artists, albums, or tracks...',
                                _CurateTab.playlists =>
                                  'Filter server playlists...',
                                _CurateTab.songs => 'Search all server songs...',
                              },
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: _searchController.clear,
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: switch (_tab) {
                        _CurateTab.artists => _buildArtistsTab(),
                        _CurateTab.playlists => _buildPlaylistsTab(),
                        _CurateTab.songs => _buildSongsTab(),
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        border: Border(
                          top: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _buildSummaryLine(),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              onPressed: _isSaving ? null : _save,
                              child: const Text('Save Library'),
                            ),
                          ],
                        ),
                      ),
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
          ? 'Include Everything • Full server catalog'
          : 'Include Everything • $excluded excluded';
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
    final selectedPlaylists =
        _playlists.where((p) => filter.isServerPlaylistIncluded(p.id)).length;
    return '$fullArtists artists · $selectedAlbums albums · $selectedPlaylists playlists';
  }

  Widget _buildArtistsTab() {
    final artists = _filteredArtists;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        if (!wide) {
          return ListView.builder(
            itemCount: artists.length,
            itemBuilder: (context, index) => _buildArtistRow(
              artists[index],
              isWide: false,
            ),
          );
        }

        final selectedGroup = artists
                .where((g) => g.key == _selectedArtistKey)
                .firstOrNull ??
            (artists.isNotEmpty ? artists.first : null);
        return Row(
          children: [
            SizedBox(
              width: 280,
              child: ListView.builder(
                itemCount: artists.length,
                itemBuilder: (context, index) => _buildArtistRow(
                  artists[index],
                  isWide: true,
                  selected: artists[index].key == selectedGroup?.key,
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: selectedGroup == null
                  ? const Center(child: Text('Select an artist'))
                  : _ArtistDetailPane(
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
    final state = _draft.artistCheckboxState(group);
    final selectedCount = _draft.includedItemCountForArtist(group);
    final totalItems = group.totalItems;
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.35),
      leading: Checkbox(
        tristate: true,
        value: state.toTristateBool(),
        onChanged: (_) => setState(() => _draft.toggleArtistWhole(group)),
      ),
      title: Text(
        group.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$selectedCount / $totalItems selected',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      trailing: isWide ? null : const Icon(Icons.chevron_right_rounded),
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
      header: AriamiSheetHeader(
        title: group.displayName,
        leading: const Icon(Icons.person_rounded),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return _ArtistDetailPane(
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

  Widget _buildPlaylistsTab() {
    final items = _filteredPlaylists;
    if (items.isEmpty) {
      return const Center(child: Text('No server playlists found'));
    }
    final filter = _draft.filter;
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final playlist = items[index];
        final included = filter.isServerPlaylistIncluded(playlist.id);
        return CheckboxListTile(
          value: included,
          title: Text(playlist.name),
          subtitle: Text('${playlist.songCount} songs'),
          onChanged: (_) {
            setState(() => _draft.togglePlaylist(playlist.id));
          },
        );
      },
    );
  }

  Widget _buildSongsTab() {
    final items = _filteredSongs;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty
              ? 'No standalone singles. Type above to search all songs.'
              : 'No matching songs found.',
        ),
      );
    }
    final filter = _draft.filter;
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final song = items[index];
        final albumArtist =
            song.albumId != null ? _albumArtistById[song.albumId!] : null;
        final included = filter.isSongIncluded(
          songId: song.id,
          artist: song.artist,
          albumId: song.albumId,
          albumArtist: albumArtist,
        );
        return CheckboxListTile(
          value: included,
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            song.albumTitle != null
                ? '${song.artist} · ${song.albumTitle}'
                : song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onChanged: (_) {
            setState(() {
              _draft.toggleSong(song, albumArtist: albumArtist);
            });
          },
        );
      },
    );
  }
}

class _ArtistDetailPane extends StatefulWidget {
  const _ArtistDetailPane({
    required this.group,
    required this.draft,
    required this.songsByAlbum,
    required this.onChanged,
  });

  final CurationArtistGroup group;
  final CurationDraft draft;
  final Map<String, List<CurationCatalogSong>> songsByAlbum;
  final VoidCallback onChanged;

  @override
  State<_ArtistDetailPane> createState() => _ArtistDetailPaneState();
}

class _ArtistDetailPaneState extends State<_ArtistDetailPane> {
  final Set<String> _expandedAlbumIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final draft = widget.draft;
    final filter = draft.filter;
    final artistWhole = draft.isArtistWholeEnabled(group.key);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        SwitchListTile(
          title: const Text('Include all albums & future releases'),
          subtitle: Text(
            'New albums synced for ${group.displayName} appear automatically.',
          ),
          value: artistWhole,
          onChanged: (value) {
            draft.setArtistAllToggle(group, value);
            widget.onChanged();
          },
        ),
        const Divider(height: 1),
        for (final album in group.albums) ...[
          CheckboxListTile(
            value: filter.isAlbumIncluded(
              albumId: album.id,
              artist: album.artist,
            ),
            title: Text(album.title),
            subtitle: Text('${album.songCount} songs'),
            secondary: IconButton(
              icon: Icon(
                _expandedAlbumIds.contains(album.id)
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              onPressed: () {
                setState(() {
                  if (!_expandedAlbumIds.remove(album.id)) {
                    _expandedAlbumIds.add(album.id);
                  }
                });
              },
            ),
            onChanged: (_) {
              draft.toggleAlbum(album);
              widget.onChanged();
            },
          ),
          if (_expandedAlbumIds.contains(album.id))
            for (final song in widget.songsByAlbum[album.id] ??
                const <CurationCatalogSong>[])
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: CheckboxListTile(
                  dense: true,
                  value: filter.isSongIncluded(
                    songId: song.id,
                    artist: song.artist,
                    albumId: album.id,
                    albumArtist: album.artist,
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (_) {
                    draft.toggleSong(song, albumArtist: album.artist);
                    widget.onChanged();
                  },
                ),
              ),
        ],
        if (group.standaloneSongs.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Standalone singles',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          for (final song in group.standaloneSongs)
            CheckboxListTile(
              dense: true,
              value: filter.isSongIncluded(
                songId: song.id,
                artist: song.artist,
              ),
              title: Text(song.title),
              onChanged: (_) {
                draft.toggleSong(song);
                widget.onChanged();
              },
            ),
        ],
      ],
    );
  }
}
