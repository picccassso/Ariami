import 'dart:async';

import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';

Future<UserLibraryCuration?> showCurateUserLibraryDialog(
  BuildContext context, {
  required ServerUserRow user,
  required WebApiClient apiClient,
}) {
  return showDialog<UserLibraryCuration>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _CurateUserLibraryDialog(
      user: user,
      apiClient: apiClient,
    ),
  );
}

enum _PickerTab {
  artists,
  playlists,
  songs,
}

class _CurateUserLibraryDialog extends StatefulWidget {
  const _CurateUserLibraryDialog({
    required this.user,
    required this.apiClient,
  });

  final ServerUserRow user;
  final WebApiClient apiClient;

  @override
  State<_CurateUserLibraryDialog> createState() =>
      _CurateUserLibraryDialogState();
}

class _CurateUserLibraryDialogState extends State<_CurateUserLibraryDialog> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  late CurationDraft _draft;
  List<CurationArtistGroup> _artistGroups = const <CurationArtistGroup>[];
  List<CurationCatalogPlaylist> _playlists = const <CurationCatalogPlaylist>[];
  List<CurationCatalogSong> _standaloneSongs = const <CurationCatalogSong>[];
  List<CurationCatalogSong>? _searchedSongs;
  bool _isSearchingSongs = false;
  Timer? _songSearchDebounce;

  String? _selectedArtistKey;
  _PickerTab _activeTab = _PickerTab.artists;

  final Map<String, List<CurationCatalogSong>> _albumSongsCache =
      <String, List<CurationCatalogSong>>{};
  final Set<String> _expandedAlbumIds = <String>{};
  final Set<String> _loadingAlbumIds = <String>{};

  @override
  void initState() {
    super.initState();
    _draft = CurationDraft(mode: LibraryCurationMode.full);
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _songSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.apiClient.getUserCuration(widget.user.userId),
        widget.apiClient.getAdminCurationCatalog(),
      ]);
      if (!mounted) return;
      final curation = results[0] as UserLibraryCuration;
      final catalog = results[1] as ({
        List<CurationCatalogAlbum> albums,
        List<CurationCatalogPlaylist> playlists,
        List<CurationCatalogSong> standaloneSongs,
      });

      final groups = CurationDraft.buildArtistGroups(
        albums: catalog.albums,
        standaloneSongs: catalog.standaloneSongs,
      );
      final playlists = List<CurationCatalogPlaylist>.from(catalog.playlists)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final standalone = List<CurationCatalogSong>.from(catalog.standaloneSongs)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      setState(() {
        _draft = CurationDraft.fromCuration(curation);
        _artistGroups = groups;
        _playlists = playlists;
        _standaloneSongs = standalone;
        _selectedArtistKey = groups.isNotEmpty ? groups.first.key : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load library catalog ($e).';
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    setState(() {});
    if (_activeTab != _PickerTab.songs) return;
    _scheduleSongSearch();
  }

  void _scheduleSongSearch() {
    _songSearchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchedSongs = null;
        _isSearchingSongs = false;
      });
      return;
    }
    _songSearchDebounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _isSearchingSongs = true);
      try {
        final songs = await widget.apiClient.getAdminCurationSongs(query: query);
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

  Future<void> _toggleAlbumExpanded(String albumId) async {
    if (_expandedAlbumIds.contains(albumId)) {
      setState(() => _expandedAlbumIds.remove(albumId));
      return;
    }
    setState(() => _expandedAlbumIds.add(albumId));
    if (_albumSongsCache.containsKey(albumId)) return;
    setState(() => _loadingAlbumIds.add(albumId));
    try {
      final songs =
          await widget.apiClient.getAdminCurationSongs(albumId: albumId);
      if (!mounted) return;
      setState(() {
        _albumSongsCache[albumId] = songs;
        _loadingAlbumIds.remove(albumId);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAlbumIds.remove(albumId));
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final saved = await widget.apiClient.putUserCuration(
        widget.user.userId,
        mode: _draft.mode,
        rules: _draft.toRules(),
        onboardingCompleted: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to save curation ($e).';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final width = (screen.width - 48).clamp(320.0, 960.0);
    final height = (screen.height - 64).clamp(420.0, 700.0);

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        side: const BorderSide(color: AppTheme.borderStrong),
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, color: AppTheme.border),
            if (!_isLoading && _error == null) ...[
              _buildToolbar(),
              const Divider(height: 1, color: AppTheme.border),
            ],
            Expanded(child: _buildBody(width)),
            const Divider(height: 1, color: AppTheme.border),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
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
                'Curate Library · ${widget.user.username}',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _draft.mode == LibraryCurationMode.full
                    ? 'Include Everything — new scans appear automatically unless excluded.'
                    : 'Curated Mode — only selected artists, albums, playlists, and songs appear.',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
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
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _TabChip(
            label: 'Artists & Albums (${_artistGroups.length})',
            selected: _activeTab == _PickerTab.artists,
            onTap: () => setState(() => _activeTab = _PickerTab.artists),
          ),
          _TabChip(
            label: 'Server Playlists (${_playlists.length})',
            selected: _activeTab == _PickerTab.playlists,
            onTap: () => setState(() => _activeTab = _PickerTab.playlists),
          ),
          _TabChip(
            label: 'Songs',
            selected: _activeTab == _PickerTab.songs,
            onTap: () {
              setState(() => _activeTab = _PickerTab.songs);
              _scheduleSongSearch();
            },
          ),
          SizedBox(
            width: 240,
            height: 34,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Filter…',
                hintStyle: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 17),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                filled: true,
                fillColor: AppTheme.surfaceRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _draft.selectAll()),
            child: const Text('Select All'),
          ),
          TextButton(
            onPressed: () => setState(() => _draft.clearAll()),
            child: const Text('Clear'),
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
                style: const TextStyle(color: AppTheme.danger),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    switch (_activeTab) {
      case _PickerTab.artists:
        return _buildSplitArtistsView(width);
      case _PickerTab.playlists:
        return _buildPlaylistsView();
      case _PickerTab.songs:
        return _buildSongsView();
    }
  }

  Widget _buildSplitArtistsView(double width) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _artistGroups
        : _artistGroups.where((group) {
            if (group.displayName.toLowerCase().contains(query)) return true;
            if (group.albums.any((a) => a.title.toLowerCase().contains(query))) {
              return true;
            }
            return group.standaloneSongs
                .any((s) => s.title.toLowerCase().contains(query));
          }).toList(growable: false);

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'No matching artists or albums.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    final selected = filtered.firstWhere(
      (g) => g.key == _selectedArtistKey,
      orElse: () => filtered.first,
    );

    final isNarrow = width < 640;
    if (isNarrow) {
      return Column(
        children: [
          Expanded(
            flex: 1,
            child: _buildArtistMasterList(filtered, selected),
          ),
          const Divider(height: 1, color: AppTheme.border),
          Expanded(
            flex: 1,
            child: _buildArtistDetailPane(selected),
          ),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 300,
          child: _buildArtistMasterList(filtered, selected),
        ),
        const VerticalDivider(width: 1, color: AppTheme.border),
        Expanded(
          child: _buildArtistDetailPane(selected),
        ),
      ],
    );
  }

  Widget _buildArtistMasterList(
    List<CurationArtistGroup> groups,
    CurationArtistGroup selected,
  ) {
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final isSelected = group.key == selected.key;
        final included = _draft.includedItemCountForArtist(group);
        final total = group.totalItems;
        final checkState = _draft.artistCheckboxState(group).toTristateBool();

        return Material(
          color: isSelected ? AppTheme.surfaceRaised : Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _selectedArtistKey = group.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Checkbox(
                    tristate: true,
                    value: checkState,
                    onChanged: (_) =>
                        setState(() => _draft.toggleArtistWhole(group)),
                  ),
                  Expanded(
                    child: Text(
                      group.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$included / $total',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtistDetailPane(CurationArtistGroup group) {
    final filter = _draft.filter;
    final artistWholeEnabled = _draft.isArtistWholeEnabled(group.key);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.displayName,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceRaised,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Include all albums & future releases by this artist',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'New music scanned for this artist will auto-appear unless an album is unchecked.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: artistWholeEnabled,
                onChanged: (val) =>
                    setState(() => _draft.setArtistAllToggle(group, val)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (group.albums.isNotEmpty) ...[
          Text(
            'Albums (${group.albums.length})',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final album in group.albums) ...[
            _buildAlbumRow(album, filter),
          ],
        ],
        if (group.standaloneSongs.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Standalone Singles (${group.standaloneSongs.length})',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final song in group.standaloneSongs)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: filter.isSongIncluded(
                songId: song.id,
                artist: song.artist,
                albumId: song.albumId,
              ),
              onChanged: (_) => setState(() => _draft.toggleSong(song)),
              title: Text(
                song.title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                song.artist,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildAlbumRow(
    CurationCatalogAlbum album,
    LibraryCurationFilter filter,
  ) {
    final isIncluded =
        filter.isAlbumIncluded(albumId: album.id, artist: album.artist);
    final isExpanded = _expandedAlbumIds.contains(album.id);
    final isLoadingTracks = _loadingAlbumIds.contains(album.id);
    final tracks = _albumSongsCache[album.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: isIncluded,
              onChanged: (_) => setState(() => _draft.toggleAlbum(album)),
            ),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _draft.toggleAlbum(album)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${album.year != null ? '${album.year} · ' : ''}${album.songCount} ${album.songCount == 1 ? 'track' : 'tracks'}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => _toggleAlbumExpanded(album.id),
              child: Text(isExpanded ? 'Hide tracks' : 'Tracks'),
            ),
          ],
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 42, bottom: 8),
            child: isLoadingTracks
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Column(
                    children: (tracks ?? const <CurationCatalogSong>[])
                        .map((song) => CheckboxListTile(
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: filter.isSongIncluded(
                                songId: song.id,
                                artist: song.artist,
                                albumId: album.id,
                                albumArtist: album.artist,
                              ),
                              onChanged: (_) => setState(
                                () => _draft.toggleSong(
                                  song,
                                  albumArtist: album.artist,
                                ),
                              ),
                              title: Text(
                                song.title,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ))
                        .toList(growable: false),
                  ),
          ),
      ],
    );
  }

  Widget _buildPlaylistsView() {
    final query = _searchController.text.trim().toLowerCase();
    final filter = _draft.filter;
    final items = query.isEmpty
        ? _playlists
        : _playlists
            .where((p) => p.name.toLowerCase().contains(query))
            .toList(growable: false);

    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No matching server playlists.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final pl = items[index];
        return CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          value: filter.isServerPlaylistIncluded(pl.id),
          onChanged: (_) => setState(() => _draft.togglePlaylist(pl.id)),
          title: Text(
            pl.name,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          ),
          subtitle: Text(
            '${pl.songCount} ${pl.songCount == 1 ? 'song' : 'songs'} · Tracks inside stay playable without adding parent albums',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSongsView() {
    final query = _searchController.text.trim();
    final filter = _draft.filter;
    if (_isSearchingSongs) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = query.isNotEmpty
        ? (_searchedSongs ?? const <CurationCatalogSong>[])
        : _standaloneSongs;

    if (items.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty
              ? 'No standalone singles found. Type above to search all catalog songs.'
              : 'No matching songs.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    final albumArtistById = <String, String>{};
    for (final group in _artistGroups) {
      for (final album in group.albums) {
        albumArtistById[album.id] = album.artist;
      }
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final song = items[index];
        final albumArtist =
            song.albumId != null ? albumArtistById[song.albumId!] : null;
        return CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          value: filter.isSongIncluded(
            songId: song.id,
            artist: song.artist,
            albumId: song.albumId,
            albumArtist: albumArtist,
          ),
          onChanged: (_) => setState(
            () => _draft.toggleSong(song, albumArtist: albumArtist),
          ),
          title: Text(
            song.title,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          ),
          subtitle: Text(
            song.albumTitle != null
                ? '${song.artist} · ${song.albumTitle}'
                : song.artist,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    final ruleCount = _draft.toRules().length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _draft.mode == LibraryCurationMode.full
                  ? (ruleCount == 0
                      ? 'Include Everything'
                      : 'Include Everything · $ruleCount override rule${ruleCount == 1 ? '' : 's'}')
                  : 'Curated Mode · $ruleCount rule${ruleCount == 1 ? '' : 's'}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _isLoading || _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Library'),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
