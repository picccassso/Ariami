import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import '../services/quick_jump_service.dart';
import '../services/sidebar_selection_controller.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'context_menu.dart';
import 'downloaded_badge.dart';
import 'hover_builder.dart';
import 'hover_surface.dart';
import 'playback_helpers.dart';
import 'playing_indicator.dart';
import 'playlist_actions.dart';
import 'playlist_artwork.dart';
import 'queue_intent.dart';
import 'shell_column_header.dart';

part 'library_sidebar/library_sidebar_artist_tile.dart';
part 'library_sidebar/library_sidebar_index_row.dart';

/// Left column: the scrollable library list. Collapses to a Spotify-style
/// cover-only rail via the toggle in its header.
class LibrarySidebar extends StatefulWidget {
  const LibrarySidebar({super.key, this.forceCollapsed = false});

  static const Duration searchDebounce = Duration(milliseconds: 100);

  final bool forceCollapsed;

  @override
  State<LibrarySidebar> createState() => _LibrarySidebarState();
}

class _LibrarySidebarState extends State<LibrarySidebar> {
  /// The kinds the list is narrowed to. Empty is "All" — every kind shows —
  /// so combinations are reachable: picking Albums and Playlists is how you
  /// hide artists without giving up either of the others.
  ///
  /// This is a standing preference, not a session filter: hiding a kind is
  /// meant to keep it hidden across launches, so it is restored in
  /// [initState] and written back on every change.
  final Set<_LibraryFilter> _filters = <_LibraryFilter>{};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  String _debouncedSearchQuery = '';

  static const _filtersPrefKey = 'library_sidebar_filters_v1';

  /// Set once the user picks a filter, so a slow preference read can never
  /// overwrite a choice they made while it was still in flight.
  bool _filtersTouched = false;

  bool _shows(_LibraryFilter kind) =>
      _filters.isEmpty || _filters.contains(kind);

  @override
  void initState() {
    super.initState();
    _restoreFilters();
  }

  Future<void> _restoreFilters() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_filtersPrefKey);
    if (saved == null || saved.isEmpty || _filtersTouched || !mounted) return;
    setState(() {
      _filters.addAll(
        // Unknown names are dropped, so a filter removed in a later build
        // can't resurrect itself out of an old preference.
        _LibraryFilter.values.where((kind) => saved.contains(kind.name)),
      );
    });
  }

  void _toggle(_LibraryFilter kind) {
    setState(() {
      _filtersTouched = true;
      if (!_filters.remove(kind)) _filters.add(kind);
    });
    _saveFilters();
  }

  void _clearFilters() {
    setState(() {
      _filtersTouched = true;
      _filters.clear();
    });
    _saveFilters();
  }

  Future<void> _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _filtersPrefKey,
      [for (final kind in _filters) kind.name],
    );
  }

  void _onSearchChanged(String value) {
    final trimmed = value.trim();
    _searchDebounceTimer?.cancel();
    if (trimmed.isEmpty) {
      if (_debouncedSearchQuery.isNotEmpty) {
        setState(() => _debouncedSearchQuery = '');
      }
      return;
    }
    _searchDebounceTimer = Timer(LibrarySidebar.searchDebounce, () {
      if (!mounted || _debouncedSearchQuery == trimmed) return;
      setState(() => _debouncedSearchQuery = trimmed);
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<PlayerNavigator>();
    final library = context.watch<LibraryController>();
    final collapsed = widget.forceCollapsed || nav.sidebarCollapsed;

    // The panel background + width animation live on the parent
    // (player_shell). Pin our content to the destination width so it never
    // reflows mid-animation (the parent clips the overflow), which keeps the
    // collapse/expand smooth and avoids transient layout overflow.
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: collapsed ? 76 : 256,
      maxWidth: collapsed ? 76 : 256,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (collapsed)
            _CollapsedHeader(onExpand: nav.toggleSidebar)
          else
            _ExpandedHeader(
              loading: library.isLoading,
              onCollapse: nav.toggleSidebar,
            ),
          if (!collapsed) ...[
            const _ServerLine(),
            _LibrarySearchField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onClear: () {
                _searchDebounceTimer?.cancel();
                _searchController.clear();
                setState(() => _debouncedSearchQuery = '');
              },
            ),
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.colors.border),
                ),
              ),
              // Each kind is an independent toggle (All clears them), so
              // two can be underlined at once. One strip, always: shrunk as a
              // group rather than wrapping if a wider font or translation
              // ever needs more than the sidebar's width.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    ShellTab(
                      label: 'All',
                      height: 39,
                      selected: _filters.isEmpty,
                      onTap: _clearFilters,
                    ),
                    for (final filter in _LibraryFilter.values) ...[
                      const SizedBox(width: 16),
                      ShellTab(
                        label: filter.label,
                        height: 39,
                        selected: _filters.contains(filter),
                        onTap: () => _toggle(filter),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          Expanded(child: _buildList(context, library, collapsed)),
        ],
      ),
    );
  }

  Widget _buildList(
      BuildContext context, LibraryController library, bool collapsed) {
    if (library.isLoading && !library.hasContent) {
      return const SizedBox.shrink();
    }
    if (library.error != null && !library.hasContent) {
      if (collapsed) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          library.error!,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        ),
      );
    }

    // Hidden entries are dropped before anything else, search included: the
    // sidebar is the one list that honours hiding, so a hidden album must not
    // reappear the moment its name is typed. Settings is the way back.
    final playlists = library.playlists
        .where((playlist) => !library.isPlaylistHidden(playlist.id))
        .toList()
      ..sort((a, b) {
        final aPinned = library.isPlaylistPinned(a.id);
        final bPinned = library.isPlaylistPinned(b.id);
        if (aPinned != bPinned) return aPinned ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final albums = library.albums
        .where((album) => !library.isAlbumHidden(album.id))
        .toList()
      ..sort((a, b) {
        final aPinned = library.isAlbumPinned(a.id);
        final bPinned = library.isAlbumPinned(b.id);
        if (aPinned != bPinned) return aPinned ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final searchQuery = _debouncedSearchQuery;
    final searchResults =
        searchQuery.isEmpty ? null : library.searchCollections(searchQuery);
    final visiblePlaylists = searchResults == null
        ? playlists
        : searchResults.playlists
            .where((playlist) => !library.isPlaylistHidden(playlist.id))
            .toList(growable: false);
    final visibleAlbums = searchResults == null
        ? albums
        : searchResults.albums
            .where((album) => !library.isAlbumHidden(album.id))
            .toList(growable: false);
    final visibleArtists = (searchQuery.isEmpty
            ? library.artists
            : library.searchArtists(searchQuery))
        .where((artist) => !library.isArtistHidden(artist.name))
        .toList(growable: false);

    final nav = context.read<PlayerNavigator>();
    // Tiles are built from a closure rather than up front: the row a
    // shift-click ranges to is an index into the *sorted* list, so the keys
    // and the selection callbacks can only be assigned after the sort below.
    final selection = context.watch<SidebarSelectionController>();
    final entries = <({
      String name,
      bool pinned,
      String key,
      VoidCallback open,
      Widget Function(SidebarEntrySelection, int?, String?) build,
    })>[
      if (_shows(_LibraryFilter.playlists))
        for (final playlist in visiblePlaylists)
          (
            name: playlist.name,
            pinned: library.isPlaylistPinned(playlist.id),
            key: 'playlist:${playlist.id}',
            open: () => nav.openPlaylist(playlist.id),
            build: (entrySelection, quickJumpIndex, letter) => _PlaylistTile(
                  playlist: playlist,
                  collapsed: collapsed,
                  selection: entrySelection,
                  quickJumpIndex: quickJumpIndex,
                  letter: letter,
                ),
          ),
      if (_shows(_LibraryFilter.albums))
        for (final album in visibleAlbums)
          (
            name: album.title,
            pinned: library.isAlbumPinned(album.id),
            key: 'album:${album.id}',
            open: () => nav.openAlbum(album.id),
            build: (entrySelection, quickJumpIndex, letter) => _AlbumTile(
                  album: album,
                  collapsed: collapsed,
                  selection: entrySelection,
                  quickJumpIndex: quickJumpIndex,
                  letter: letter,
                ),
          ),
      if (_shows(_LibraryFilter.artists))
        for (final artist in visibleArtists)
          (
            name: artist.name,
            pinned: false,
            key: 'artist:${artist.name}',
            open: () => nav.openArtist(artist.name),
            build: (entrySelection, quickJumpIndex, letter) => _ArtistTile(
                  artist: artist,
                  collapsed: collapsed,
                  selection: entrySelection,
                  quickJumpIndex: quickJumpIndex,
                  letter: letter,
                ),
          ),
    ];
    // A single kind keeps the order it arrived in — search rank, or pinned
    // first. Mixing kinds has no such order to keep, so they interleave
    // alphabetically with pinned collections held at the top.
    if (_filters.length != 1) {
      entries.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    final visibleKeys = [for (final entry in entries) entry.key];
    // Published for the floating selection bar, which lives outside the
    // sidebar and so cannot see this list itself.
    selection.visibleKeys = visibleKeys;

    final hasAllSongs =
        _filters.isEmpty && searchQuery.isEmpty && library.songs.isNotEmpty;

    final quickJump = context.read<QuickJumpService?>();
    if (quickJump != null) {
      quickJump.targets = <VoidCallback>[
        if (hasAllSongs) nav.openAllSongs,
        for (final entry in entries) entry.open,
      ];
    }

    // Index letters mark where the alphabet turns over. Only an unsearched
    // list is alphabetical (search keeps its rank order), and pinned entries
    // sit above the alphabet with a pin of their own.
    final letters = List<String?>.filled(entries.length, null);
    if (searchQuery.isEmpty) {
      String? previous;
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].pinned) continue;
        final letter = _indexLetter(entries[i].name);
        if (letter != previous) letters[i] = letter;
        previous = letter;
      }
    }

    final items = <Widget>[
      for (var index = 0; index < entries.length; index++) ...[
        () {
          final itemNumber = (hasAllSongs ? 1 : 0) + index + 1;
          final quickJumpNumber = itemNumber <= 9 ? itemNumber : null;
          return entries[index].build(
            SidebarEntrySelection(
              selected: selection.isSelected(entries[index].key),
              claimTap: () => _claimSelectionTap(selection, visibleKeys, index),
            ),
            quickJumpNumber,
            letters[index],
          );
        }(),
      ],
    ];

    // Songs the scanner left outside an album (loose files, singles) exist in
    // no collection, so keep their entry at the top of the unfiltered list.
    if (hasAllSongs) {
      items.insert(
        0,
        _AllSongsTile(
          collapsed: collapsed,
          quickJumpIndex: 1,
        ),
      );
    }

    if (items.isEmpty) {
      if (collapsed) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          searchQuery.isEmpty
              ? 'Nothing here yet. Make sure your library has been scanned.'
              : 'No matches for "$searchQuery".',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: collapsed ? 0 : 8),
      itemCount: items.length,
      itemBuilder: (_, index) => items[index],
    );
  }
}

/// The index letter [name] files under: its first letter, or # for names
/// that start with a digit or symbol.
String _indexLetter(String name) {
  final first = name.trim().isEmpty ? '#' : name.trim()[0].toUpperCase();
  return RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
}

class SidebarEntrySelection {
  const SidebarEntrySelection({
    required this.selected,
    required this.claimTap,
  });

  final bool selected;

  /// Offers a click to the selection. Returns true when it was taken, in which
  /// case the row must not navigate — this is what stops a cmd-click from
  /// selecting an album *and* opening it.
  final bool Function() claimTap;

  static const none = SidebarEntrySelection(selected: false, claimTap: _never);

  static bool _never() => false;
}

/// Routes a click on row [index] to the selection, mirroring the track list:
/// cmd/ctrl-click or shift-click starts selecting, and once the mode is on
/// every plain click selects too. cmd is the modifier on macOS, where
/// ctrl-click is the platform's secondary click.
bool _claimSelectionTap(
  SidebarSelectionController selection,
  List<String> visibleKeys,
  int index,
) {
  final keyboard = HardwareKeyboard.instance;
  final shift = keyboard.isShiftPressed;
  final meta = defaultTargetPlatform == TargetPlatform.macOS
      ? keyboard.isMetaPressed
      : keyboard.isControlPressed;
  if (!selection.active && !shift && !meta) return false;
  return selection.handleRowTap(
    visibleKeys,
    index,
    shift: shift,
    meta: meta,
  );
}

/// The kinds of entry the sidebar lists, in the order their chips appear.
/// Each chip is an independent toggle; the separate All chip clears them.
enum _LibraryFilter {
  albums('Albums'),
  playlists('Playlists'),
  artists('Artists');

  const _LibraryFilter(this.label);

  final String label;
}

class _LibrarySearchField extends StatelessWidget {
  const _LibrarySearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;
    final borderRadius = BorderRadius.circular(PlayerTheme.tileRadius);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: TextField(
        key: const Key('library-search-field'),
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 13, color: colors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Filter library',
          hintStyle: TextStyle(color: colors.textSecondary),
          prefixIcon:
              Icon(Icons.search_rounded, size: 18, color: colors.textSecondary),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 34),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Clear library search',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 17),
                color: colors.textSecondary,
                onPressed: onClear,
              );
            },
          ),
          filled: true,
          fillColor: colors.surfaceHigh,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          border: OutlineInputBorder(
            borderRadius: borderRadius,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: borderRadius,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: borderRadius,
            borderSide: BorderSide(color: primary),
          ),
        ),
      ),
    );
  }
}

/// Leaves room for the macOS traffic lights, which float over this corner
/// of the frameless window.
double _trafficLightInset(BuildContext context) {
  final host = maybeReadHost(context);
  return (host?.hasMacWindowChrome ?? false) ? host!.macTrafficLightInset : 0;
}

class _ExpandedHeader extends StatelessWidget {
  const _ExpandedHeader({required this.loading, required this.onCollapse});
  final bool loading;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return ShellColumnHeader(
      padding: EdgeInsets.only(left: 16 + _trafficLightInset(context), right: 6),
      children: [
        Expanded(
          child: Text(
            'Ariami',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: PlayerTheme.display(26, color: context.colors.textPrimary)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton(
          tooltip: 'New playlist',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_rounded, size: 20),
          color: context.colors.textSecondary,
          onPressed: () => _createPlaylist(context),
        ),
        IconButton(
          tooltip: 'Collapse library',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_double_arrow_left_rounded, size: 20),
          color: context.colors.textSecondary,
          onPressed: onCollapse,
        ),
      ],
    );
  }
}

class _CollapsedHeader extends StatelessWidget {
  const _CollapsedHeader({required this.onExpand});
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final expand = IconButton(
      tooltip: 'Expand library',
      icon: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 20),
      color: context.colors.textSecondary,
      onPressed: onExpand,
    );
    // On desktop macOS the header row belongs to the traffic lights; the expand
    // button drops below it.
    final hasMacChrome = maybeReadHost(context)?.hasMacWindowChrome ?? false;
    if (hasMacChrome) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ShellColumnHeader(children: []),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(child: expand),
          ),
        ],
      );
    }
    return ShellColumnHeader(
      children: [Expanded(child: Center(child: expand))],
    );
  }
}

/// Which server the library comes from, under the wordmark.
class _ServerLine extends StatelessWidget {
  const _ServerLine();

  @override
  Widget build(BuildContext context) {
    final (name, offline) =
        context.select<ConnectionController, (String?, bool)>(
            (c) => (c.serverInfo?.name, c.isOfflineActive));
    final text = offline
        ? 'Offline, playing downloads'
        : name == null || name.isEmpty
            ? null
            : 'Connected to $name';
    if (text == null) return const SizedBox(height: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, color: context.colors.textSecondary),
      ),
    );
  }
}

/// Opens the flat, whole-library [SongsView]. Sits at the top of the sidebar
/// list in the same shape as an album or playlist tile, with a tinted icon
/// standing in for artwork.
class _AllSongsTile extends StatelessWidget {
  const _AllSongsTile({
    required this.collapsed,
    this.quickJumpIndex,
  });
  final bool collapsed;
  final int? quickJumpIndex;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<PlayerNavigator>();
    final library = context.watch<LibraryController>();
    final audio = context.watch<AudioController>();
    final playing = audio.sourceId == AudioController.allSongsSource;
    final active = playing || nav.current.kind == PlayerViewKind.songs;
    final art = _AllSongsArtwork(
      size: collapsed ? 46 : _IndexRow.artSize,
      active: active,
    );

    if (collapsed) {
      return _CollapsedTile(
        tooltip: 'All Songs',
        onTap: nav.openAllSongs,
        child: _PinnedArtwork(
          artwork: art,
          pinned: false,
          playing: playing,
          animating: playing && audio.isPlaying,
        ),
      );
    }
    return _IndexRow(
      title: 'All Songs',
      meta: '${library.songs.length}',
      art: art,
      active: active,
      playing: playing,
      animating: playing && audio.isPlaying,
      quickJumpIndex: quickJumpIndex,
      sourceId: AudioController.allSongsSource,
      onStart: () => playAllSongs(context),
      onTap: nav.openAllSongs,
    );
  }
}

class _AllSongsArtwork extends StatelessWidget {
  const _AllSongsArtwork({required this.size, required this.active});
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PlayerTheme.coverRadius),
        color: accent.withValues(alpha: active ? 0.28 : 0.16),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.5,
        color: accent,
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.album,
    this.collapsed = false,
    this.selection = SidebarEntrySelection.none,
    this.quickJumpIndex,
    this.letter,
  });
  final Album album;
  final bool collapsed;
  final SidebarEntrySelection selection;
  final int? quickJumpIndex;

  /// The index letter, set on the first entry under each letter.
  final String? letter;

  @override
  Widget build(BuildContext context) {
    final nav = context.read<PlayerNavigator>();
    final library = context.watch<LibraryController>();
    final audio = context.watch<AudioController>();
    final client = context.read<ConnectionController>().client;
    final downloaded = maybeSelectProvider<PlayerDownloadsBridge?, bool>(
      context,
      (d) => d?.isAlbumDownloaded(album.id, album.songCount) ?? false,
      fallback: false,
    );
    final art = ArtworkWithDownloadedBadge(
      downloaded: downloaded,
      artwork: Artwork(
        client: client,
        albumId: album.id,
        size: collapsed ? 46 : _IndexRow.artSize,
      ),
    );
    final pinned = library.isAlbumPinned(album.id);
    final playing = audio.sourceId == AudioController.albumSource(album.id);
    final animating = playing && audio.isPlaying;
    void open() {
      if (selection.claimTap()) return;
      nav.openAlbum(album.id);
    }

    if (collapsed) {
      return _CollapsedTile(
        tooltip: album.title,
        onTap: open,
        onSecondaryTapDown: (details) =>
            _showAlbumMenu(context, details.globalPosition, album),
        child: _PinnedArtwork(
          artwork: art,
          pinned: pinned,
          playing: playing,
          animating: animating,
          selected: selection.selected,
        ),
      );
    }
    return _IndexRow(
      title: album.title,
      subtitle: album.artist,
      letter: letter,
      pinned: pinned,
      active: playing,
      playing: playing,
      animating: animating,
      art: art,
      selection: selection,
      quickJumpIndex: quickJumpIndex,
      sourceId: AudioController.albumSource(album.id),
      onStart: () => playAlbum(context, album.id),
      onTap: open,
      onSecondaryTapDown: (details) =>
          _showAlbumMenu(context, details.globalPosition, album),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.playlist,
    this.collapsed = false,
    this.selection = SidebarEntrySelection.none,
    this.quickJumpIndex,
    this.letter,
  });
  final PlaylistSummary playlist;
  final bool collapsed;
  final SidebarEntrySelection selection;
  final int? quickJumpIndex;

  /// The index letter, set on the first entry under each letter.
  final String? letter;

  @override
  Widget build(BuildContext context) {
    final nav = context.read<PlayerNavigator>();
    final library = context.watch<LibraryController>();
    final audio = context.watch<AudioController>();
    final downloaded = maybeSelectProvider<PlayerDownloadsBridge?, bool>(
      context,
      (d) => d?.areAllSongsDownloaded(playlist.songIds) ?? false,
      fallback: false,
    );
    final art = ArtworkWithDownloadedBadge(
      downloaded: downloaded,
      artwork: PlaylistArtwork(
        playlist: playlist,
        size: collapsed ? 46 : _IndexRow.artSize,
        borderRadius: PlayerTheme.coverRadius,
      ),
    );
    final pinned = library.isPlaylistPinned(playlist.id);
    final playing =
        audio.sourceId == AudioController.playlistSource(playlist.id);
    final animating = playing && audio.isPlaying;
    void open() {
      if (selection.claimTap()) return;
      nav.openPlaylist(playlist.id);
    }

    if (collapsed) {
      return _PlaylistDropTarget(
        playlist: playlist,
        child: _CollapsedTile(
          tooltip: playlist.name,
          onTap: open,
          onSecondaryTapDown: (details) =>
              _showPlaylistMenu(context, details.globalPosition, playlist),
          child: _PinnedArtwork(
            artwork: art,
            pinned: pinned,
            playing: playing,
            animating: animating,
            selected: selection.selected,
          ),
        ),
      );
    }
    return _PlaylistDropTarget(
      playlist: playlist,
      child: _IndexRow(
        title: playlist.name,
        meta: '${playlist.songCount}',
        letter: letter,
        pinned: pinned,
        active: playing,
        playing: playing,
        animating: animating,
        art: art,
        selection: selection,
        quickJumpIndex: quickJumpIndex,
        sourceId: AudioController.playlistSource(playlist.id),
        onStart: () => playPlaylist(context, playlist),
        onTap: open,
        onSecondaryTapDown: (details) =>
            _showPlaylistMenu(context, details.globalPosition, playlist),
      ),
    );
  }
}

/// Accepts a [TrackRow] drag: dropping a song onto a sidebar playlist adds it
/// to that playlist, with an accent highlight while hovering.
class _PlaylistDropTarget extends StatelessWidget {
  const _PlaylistDropTarget({required this.playlist, required this.child});
  final PlaylistSummary playlist;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return DragTarget<Track>(
      onAcceptWithDetails: (details) =>
          _addDroppedTrack(context, playlist, details.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        // The border is always painted (transparent when idle) so hovering
        // never shifts the tile's layout.
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
            color: hovering ? accent.withValues(alpha: 0.12) : null,
            border: Border.all(
              color: hovering ? accent : Colors.transparent,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

Future<void> _addDroppedTrack(
  BuildContext context,
  PlaylistSummary playlist,
  Track track,
) async {
  final library = context.read<LibraryController>();
  final alreadyIn =
      library.playlistTracks(playlist).any((t) => t.id == track.id);
  if (alreadyIn) {
    _toast(context, '"${track.title}" is already in "${playlist.name}"');
    return;
  }
  await library.addTrackToPlaylist(playlist.id, track.id);
  if (!context.mounted) return;
  _toast(context, 'Added to "${playlist.name}"');
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
  );
}

class _CollapsedTile extends StatelessWidget {
  const _CollapsedTile({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.onSecondaryTapDown,
  });
  final String tooltip;
  final VoidCallback onTap;

  /// Null on tiles with no context menu (the All Songs entry).
  final GestureTapDownCallback? onSecondaryTapDown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Center(
        child: Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 500),
          child: GestureDetector(
            onSecondaryTapDown: onSecondaryTapDown,
            child: InkWell(
              borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
              onTap: onTap,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The check that marks a selected row. Sits where the eye lands last in the
/// expanded list, and over the artwork in the collapsed rail.
class _SelectedCheck extends StatelessWidget {
  const _SelectedCheck({this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.check_circle_rounded,
      size: size,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}

class _QuickJumpBadge extends StatelessWidget {
  const _QuickJumpBadge({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = context.select<QuickJumpService?, bool>(
      (s) => s?.highlightedIndex == number - 1,
    );
    final isActive = context.select<QuickJumpService?, bool>(
      (s) => s?.isActive ?? false,
    );
    final visible = isActive || isHighlighted;
    return Positioned(
      top: -3,
      left: -3,
      child: IgnorePointer(
        child: AnimatedScale(
          scale: visible ? (isHighlighted ? 1.12 : 1.0) : 0.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              key: ValueKey('quick-jump-badge-$number'),
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                color: context.colors.textPrimary,
                borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
              ),
              alignment: Alignment.center,
              child: Text(
                '$number',
                style: TextStyle(
                  color: context.colors.base,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinnedArtwork extends StatelessWidget {
  const _PinnedArtwork({
    required this.artwork,
    required this.pinned,
    this.playing = false,
    this.animating = false,
    this.selected = false,
  });
  final Widget artwork;
  final bool pinned;
  final bool playing;
  final bool animating;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        artwork,
        if (selected)
          Positioned(
            left: -3,
            top: -3,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: context.colors.surface,
                shape: BoxShape.circle,
              ),
              child: const _SelectedCheck(size: 13),
            ),
          ),
        if (pinned)
          Positioned(
            right: -3,
            top: -3,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.colors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.push_pin_rounded, size: 12, color: accent),
            ),
          ),
        if (playing)
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.colors.surface,
                shape: BoxShape.circle,
              ),
              child: PlayingBars(playing: animating, color: accent, size: 12),
            ),
          ),
      ],
    );
  }
}

/// Hover-reveal play button over the sidebar artwork, mirroring the
/// detail-page [CollectionPlayButton]: while [sourceId] is what's playing and
/// the "Play button follows playback" setting is on, it becomes a Pause that
/// toggles playback; otherwise it starts the collection via [onStart] (which
/// also honours the shift/cmd queue modifiers).
class _SidebarPlayButton extends StatelessWidget {
  const _SidebarPlayButton({
    required this.sourceId,
    required this.onStart,
  });

  final String sourceId;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final scheme = Theme.of(context).colorScheme;
    final mirroring = audio.playButtonsFollowPlayback &&
        audio.sourceId == sourceId &&
        audio.currentTrack != null;
    final playing = mirroring && (audio.isPlaying || audio.isLoading);
    return Material(
      color: scheme.secondary,
      borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
        mouseCursor: SystemMouseCursors.click,
        onTap: () {
          // Mirrors CollectionPlayButton: a held queue modifier queues the
          // collection even while it's the one playing; otherwise a playing
          // collection toggles, and anything else starts.
          if (mirroring && readQueueIntent() == QueueIntent.play) {
            audio.togglePlayPause();
          } else {
            onStart();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 16,
            color: scheme.onSecondary,
          ),
        ),
      ),
    );
  }
}

Future<void> _showAlbumMenu(
  BuildContext context,
  Offset position,
  Album album,
) async {
  await showCollectionContextMenu(context, position, album: album);
}

Future<void> _showArtistMenu(
  BuildContext context,
  Offset position,
  String name,
) async {
  await showCollectionContextMenu(context, position, artist: name);
}

Future<void> _createPlaylist(BuildContext context) async {
  final navigator = context.read<PlayerNavigator>();
  final id = await showCreatePlaylistDialog(context);
  if (id != null) navigator.openPlaylist(id);
}

Future<void> _showPlaylistMenu(
  BuildContext context,
  Offset position,
  PlaylistSummary playlist,
) async {
  final navigator = context.read<PlayerNavigator>();
  await showCollectionContextMenu(context, position, playlist: playlist);
  // The shared menu deletes without navigating, so step off a deleted
  // playlist we're currently viewing.
  if (!context.mounted) return;
  final stillExists = context
      .read<LibraryController>()
      .playlists
      .any((p) => p.id == playlist.id);
  if (!stillExists &&
      navigator.current.kind == PlayerViewKind.playlist &&
      navigator.current.id == playlist.id) {
    navigator.goBack();
  }
}
