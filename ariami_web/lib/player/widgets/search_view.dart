import 'dart:async';

import 'package:ariami_core/models/library_curation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_navigator.dart';
import '../theme/player_theme.dart';
import 'artwork_image_provider.dart';
import 'browse_view.dart';
import 'context_menu.dart';
import 'hover_builder.dart';
import 'playlist_artwork.dart';
import 'queue_intent.dart';
import 'track_list.dart';

/// Plays a single track selected from search, replacing the queue with just
/// that track (rather than queuing every search match) and recording it in
/// recent searches. The search field is intentionally left untouched so the
/// user keeps their results until they clear it themselves (via the field's X).
void playFromSearch(BuildContext context, Track track) {
  context.read<AudioController>().playTrack(track);
  context.read<LibraryController>().addRecentSearch(track);
}

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  bool _includeFullCatalog = false;
  SearchQueryHolder? _holder;
  LibraryController? _library;
  LibrarySearchResults _results = LibrarySearchResults.empty;
  String _resultsQuery = '';
  bool _resultsIncludeFull = false;
  bool _isSearching = false;
  int _searchGeneration = 0;

  String? _lastQuery;
  bool? _lastIncludeFull;
  List<Track>? _lastSongsRef;
  List<Album>? _lastAlbumsRef;
  List<PlaylistSummary>? _lastPlaylistsRef;
  LibraryCurationFilter? _lastCurationFilter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final holder = context.read<SearchQueryHolder>();
    if (!identical(holder, _holder)) {
      _holder?.query.removeListener(_onQueryChanged);
      _holder = holder..query.addListener(_onQueryChanged);
    }
    final library = context.read<LibraryController>();
    if (!identical(library, _library)) {
      _library?.removeListener(_onLibraryChanged);
      _library = library..addListener(_onLibraryChanged);
    }
    if (library.curationFilter.isPassThrough && _includeFullCatalog) {
      _includeFullCatalog = false;
    }
    _runSearch();
  }

  @override
  void dispose() {
    _holder?.query.removeListener(_onQueryChanged);
    _library?.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onQueryChanged() => _runSearch();

  void _onLibraryChanged() {
    final library = _library;
    if (!mounted || library == null) return;
    if (library.curationFilter.isPassThrough && _includeFullCatalog) {
      _includeFullCatalog = false;
    }
    _runSearch(force: !library.hasContent);
  }

  void _toggleFullCatalog() {
    setState(() => _includeFullCatalog = !_includeFullCatalog);
    _runSearch();
  }

  void _runSearch({bool force = false}) {
    final holder = _holder;
    final library = _library;
    if (holder == null || library == null) return;
    final rawQuery = holder.query.value;
    if (rawQuery.trim().isEmpty) {
      _searchGeneration++;
      holder.songs = Future<List<Track>>.value(const <Track>[]);
      _lastQuery = rawQuery;
      _lastIncludeFull = false;
      if (_results != LibrarySearchResults.empty ||
          _resultsQuery.isNotEmpty ||
          _resultsIncludeFull ||
          _isSearching) {
        if (mounted) {
          setState(() {
            _results = LibrarySearchResults.empty;
            _resultsQuery = '';
            _resultsIncludeFull = false;
            _isSearching = false;
          });
        } else {
          _results = LibrarySearchResults.empty;
          _resultsQuery = '';
          _resultsIncludeFull = false;
          _isSearching = false;
        }
      }
      return;
    }

    final includeFullCatalog =
        !library.curationFilter.isPassThrough && _includeFullCatalog;
    if (!force &&
        rawQuery == _lastQuery &&
        includeFullCatalog == _lastIncludeFull &&
        identical(library.songs, _lastSongsRef) &&
        identical(library.albums, _lastAlbumsRef) &&
        identical(library.playlists, _lastPlaylistsRef) &&
        library.curationFilter == _lastCurationFilter) {
      return;
    }
    _lastQuery = rawQuery;
    _lastIncludeFull = includeFullCatalog;
    _lastSongsRef = library.songs;
    _lastAlbumsRef = library.albums;
    _lastPlaylistsRef = library.playlists;
    _lastCurationFilter = library.curationFilter;

    final generation = ++_searchGeneration;
    _isSearching = true;
    final search =
        library.searchAsync(rawQuery, includeFullCatalog: includeFullCatalog);
    holder.songs = search.then((results) => results.songs);
    search.then((results) {
      if (!mounted || generation != _searchGeneration) return;
      _prefetchVisibleSearchThumbnails(results);
      setState(() {
        _results = results;
        _resultsQuery = rawQuery;
        _resultsIncludeFull = includeFullCatalog;
        _isSearching = false;
      });
    });
  }

  void _prefetchVisibleSearchThumbnails(LibrarySearchResults results) {
    final client = context.read<ConnectionController>().client;
    if (client == null) return;
    final albumIds = <String>{};
    final songIds = <String>{};
    for (final t in results.songs.take(30)) {
      if (t.albumId != null && t.albumId!.isNotEmpty) {
        albumIds.add(t.albumId!);
      } else if (t.id.isNotEmpty) {
        songIds.add(t.id);
      }
      if (albumIds.length + songIds.length >= 25) break;
    }
    if (albumIds.isNotEmpty || songIds.isNotEmpty) {
      unawaited(
        ArtworkImageProvider.prefetchBatch(
          client,
          albumIds: albumIds,
          songIds: songIds,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final holder = context.read<SearchQueryHolder>();
    final library = context.read<LibraryController>();
    final filter = context.select<LibraryController, LibraryCurationFilter>(
      (l) => l.curationFilter,
    );
    final recentSearches = context.select<LibraryController, List<Track>>(
      (l) => l.recentSearches,
    );

    return ValueListenableBuilder<String>(
      valueListenable: holder.query,
      builder: (context, value, _) {
        if (value.trim().isEmpty) {
          return const _SearchEmptyState();
        }
        final showCatalogScopeBar = !filter.isPassThrough;
        final includeFullCatalog = showCatalogScopeBar && _includeFullCatalog;
        final results = _results;

        if (results.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showCatalogScopeBar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: _CatalogScopeBar(
                    includeFullCatalog: includeFullCatalog,
                    onToggle: _toggleFullCatalog,
                  ),
                ),
              Expanded(
                child: _isSearching &&
                        (_resultsQuery != value ||
                            _resultsIncludeFull != includeFullCatalog)
                    ? const SizedBox.shrink()
                    : Center(
                        child: Text(
                          'No results for "$value"',
                          style: TextStyle(color: context.colors.textSecondary),
                        ),
                      ),
              ),
            ],
          );
        }

        final recentIds = {for (final r in recentSearches) r.id};

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              sliver: SliverMainAxisGroup(
                slivers: [
                  if (showCatalogScopeBar)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _CatalogScopeBar(
                          includeFullCatalog: includeFullCatalog,
                          onToggle: _toggleFullCatalog,
                        ),
                      ),
                    ),
                  if (results.songs.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: _Heading('Songs'),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: results.songs.length,
                      itemBuilder: (context, i) {
                        final t = results.songs[i];
                        // Rebuild only the affected rows as the ↑/↓ highlight moves.
                        return ValueListenableBuilder<int>(
                          valueListenable: holder.selectedIndex,
                          builder: (context, selected, _) {
                            final inLibrary = filter.isSongIncluded(
                              songId: t.id,
                              artist: t.artist,
                              albumId: t.albumId,
                              albumArtist: t.albumArtist,
                            );
                            return TrackRow(
                              track: t,
                              context: <Track>[t],
                              showArtwork: true,
                              showAlbum: true,
                              selected: selected == i,
                              onPlayOverride: (track) =>
                                  playFromSearch(context, track),
                              inRecentSearch: recentIds.contains(t.id),
                              showInlinePlayingBars: true,
                              lyricSnippet: results.lyricSnippets[t.id],
                              trailing: includeFullCatalog && !inLibrary
                                  ? _AddToLibraryPill(
                                      onPressed: () =>
                                          library.addTargetsToLibrary(
                                        songIds: [t.id],
                                      ),
                                    )
                                  : null,
                            );
                          },
                        );
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                  if (results.albums.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: _Heading('Albums'),
                      ),
                    ),
                    SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisExtent: 240,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final a = results.albums[i];
                          return Stack(
                            children: [
                              Positioned.fill(child: AlbumCard(album: a)),
                              if (includeFullCatalog &&
                                  !filter.isAlbumIncluded(
                                    albumId: a.id,
                                    artist: a.artist,
                                  ))
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                    ),
                                    onPressed: () =>
                                        library.addTargetsToLibrary(
                                      albumIds: [a.id],
                                    ),
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Add'),
                                  ),
                                ),
                            ],
                          );
                        },
                        childCount: results.albums.length,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                  if (results.playlists.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: _Heading('Playlists'),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: results.playlists.length,
                      itemBuilder: (context, i) {
                        final p = results.playlists[i];
                        return GestureDetector(
                          onSecondaryTapDown: (details) =>
                              showCollectionContextMenu(
                            context,
                            details.globalPosition,
                            playlist: p,
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: PlaylistArtwork(playlist: p, size: 48),
                            title: Text(p.name),
                            subtitle: Text('${p.songCount} songs'),
                            trailing: includeFullCatalog &&
                                    !filter.isServerPlaylistIncluded(p.id)
                                ? _AddToLibraryPill(
                                    onPressed: () =>
                                        library.addTargetsToLibrary(
                                      playlistIds: [p.id],
                                    ),
                                  )
                                : null,
                            onTap: () => context
                                .read<PlayerNavigator>()
                                .openPlaylist(p.id),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CatalogScopeBar extends StatelessWidget {
  const _CatalogScopeBar({
    required this.includeFullCatalog,
    required this.onToggle,
  });

  final bool includeFullCatalog;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          selected: includeFullCatalog,
          onSelected: (_) => onToggle(),
          avatar: Icon(
            includeFullCatalog
                ? Icons.public_rounded
                : Icons.library_music_rounded,
            size: 16,
          ),
          label: const Text('Search full server catalog'),
        ),
        Text(
          includeFullCatalog
              ? 'Showing all server tracks & albums (+ Add to keep)'
              : 'Showing your curated library only',
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _AddToLibraryPill extends StatelessWidget {
  const _AddToLibraryPill({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded, size: 16),
      label: const Text('Add'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    final recents = context.watch<LibraryController>().recentSearches;
    if (recents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded,
                size: 64, color: context.colors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Start typing to search',
              style: PlayerTheme.heading(22, color: context.colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Songs, albums and playlists, by name or artist.',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      itemCount: recents.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _Heading('Recent searches'),
                TextButton(
                  onPressed: () {
                    final library = context.read<LibraryController>();
                    final cleared = library.recentSearches;
                    library.clearRecentSearches();
                    showUndoToast(
                      ScaffoldMessenger.maybeOf(context),
                      'Recent searches cleared',
                      onUndo: () => library.restoreRecentSearches(cleared),
                    );
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          );
        }
        final t = recents[index - 1];
        return TrackRow(
          key: ValueKey(t.id),
          track: t,
          context: <Track>[t],
          showArtwork: true,
          showAlbum: true,
          showInlinePlayingBars: true,
          onPlayOverride: (track) => playFromSearch(context, track),
          trailing: _RemoveFromSearchButton(
            onRemove: () =>
                context.read<LibraryController>().removeRecentSearch(t.id),
          ),
        );
      },
    );
  }
}

class _RemoveFromSearchButton extends StatelessWidget {
  const _RemoveFromSearchButton({required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Remove from search',
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hover) => Listener(
          onPointerDown: (event) {
            if (event.buttons == kPrimaryButton) {
              onRemove();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: hover
                  ? context.colors.textPrimary
                  : context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
