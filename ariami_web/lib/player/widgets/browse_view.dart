import 'package:ariami_core/services/recommendations/music_recommendation_models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'curate_library_dialog.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_navigator.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'artist_link.dart';
import 'context_menu.dart';
import 'downloaded_badge.dart';
import 'genre_label.dart';
import 'home_highlights.dart';
import 'home_most_played.dart';
import 'home_now_playing.dart';
import 'hover_builder.dart';
import 'hover_surface.dart';
import 'playback_helpers.dart';
import 'playing_indicator.dart';
import 'playlist_artwork.dart';
import 'record_tile.dart';
import 'scroll_rail.dart';

/// Home view: what's playing, recents/pinned rails, capped playlists and an album
/// shelf that links out to the full [AlbumsView].
class BrowseView extends StatelessWidget {
  const BrowseView({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();

    if (library.isLoading && !library.hasContent) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!library.hasContent) {
      return _EmptyLibrary(error: library.error);
    }
    if (!library.hasVisibleContent) {
      return const _EmptyCuratedLibrary();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 48),
      children: [
        const HomeNowPlaying(),
        const SizedBox(height: 44),
        const JumpBackInRow(),
        const _PinnedShelf(),
        const HomeMostPlayed(),
        if (library.playlists.isNotEmpty) ...[
          const _PlaylistSection(),
          const SizedBox(height: 28),
        ],
        const _AlbumShelf(),
      ],
    );
  }
}

class _PinnedShelf extends StatelessWidget {
  const _PinnedShelf();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final albumsById = <String, Album>{
      for (final album in library.albums) album.id: album,
    };
    final playlistsById = <String, PlaylistSummary>{
      for (final playlist in library.playlists) playlist.id: playlist,
    };
    final targets = <_PinnedTarget>[];
    // Resolve every pin against locally-known content rather than trusting the
    // server's `missing` flag: a pinned created playlist has no catalog entry
    // (so the server marks it missing) but does resolve here via its synced
    // edit. Pins that resolve to nothing on this client are simply skipped.
    for (final pin in library.pins) {
      if (pin.type == 'album') {
        final album = albumsById[pin.targetId];
        if (album != null) targets.add(_PinnedTarget.album(album));
      } else if (pin.type == 'playlist') {
        final playlist = playlistsById[pin.targetId];
        if (playlist != null) {
          targets.add(_PinnedTarget.playlist(playlist));
        }
      }
    }
    if (targets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Pinned'),
        const SizedBox(height: 12),
        ScrollRail(
          child: Row(
            children: [
              for (var i = 0; i < targets.length; i++) ...[
                if (i > 0) const SizedBox(width: 20),
                SizedBox(
                  width: 176,
                  height: 226,
                  child: targets[i].album != null
                      ? AlbumCard(album: targets[i].album!)
                      : _PinnedPlaylistCard(playlist: targets[i].playlist!),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _PinnedTarget {
  const _PinnedTarget._({this.album, this.playlist});

  factory _PinnedTarget.album(Album album) => _PinnedTarget._(album: album);
  factory _PinnedTarget.playlist(PlaylistSummary playlist) =>
      _PinnedTarget._(playlist: playlist);

  final Album? album;
  final PlaylistSummary? playlist;
}

class _PinnedPlaylistCard extends StatelessWidget {
  const _PinnedPlaylistCard({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final playing =
        audio.sourceId == AudioController.playlistSource(playlist.id);
    return RecordTile(
      cover: (size) => PlaylistArtwork(
        playlist: playlist,
        size: size,
        borderRadius: PlayerTheme.coverRadius,
      ),
      title: playlist.name,
      subtitle: Text(
        '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
        style: const TextStyle(fontFeatures: PlayerTheme.tabular),
      ),
      playing: playing,
      animating: playing && audio.isPlaying,
      unavailable:
          collectionUnavailableOffline(context, songIds: playlist.songIds),
      onOpen: () => context.read<PlayerNavigator>().openPlaylist(playlist.id),
      onPlay: () => playPlaylist(context, playlist),
      onSecondaryTapDown: (details) => showCollectionContextMenu(
        context,
        details.globalPosition,
        playlist: playlist,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: PlayerTheme.heading(22, color: context.colors.textPrimary),
    );
  }
}

/// The small trailing affordance next to a section header ("Show all" etc),
/// styled to match "Recently played"'s Clear all button.
class _SectionAction extends StatelessWidget {
  const _SectionAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: context.colors.textSecondary,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Home "Albums" section: a single capped rail. Albums already shown in the
/// Pinned shelf are skipped, and "Show all" opens the full [AlbumsView].
class _AlbumShelf extends StatelessWidget {
  const _AlbumShelf();

  static const _maxCards = 12;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    var albums = library.albums
        .where((album) => !library.isAlbumPinned(album.id))
        .toList();
    if (albums.isEmpty) albums = library.albums; // every album is pinned
    if (albums.isEmpty) return const SizedBox.shrink();
    final shelf = albums.take(_AlbumShelf._maxCards).toList();

    // One region wraps header + rail so the scrubber reveals while the
    // pointer is anywhere over the section, like "Recently played".
    return HoverBuilder(
      builder: (context, hover) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionHeader('Albums'),
              const Spacer(),
              _SectionAction(
                label: 'Show all ${library.albums.length}',
                onPressed: () =>
                    context.read<PlayerNavigator>().openAllAlbums(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ScrollRail(
            revealScrubber: hover,
            child: Row(
              children: [
                for (var i = 0; i < shelf.length; i++) ...[
                  if (i > 0) const SizedBox(width: 20),
                  SizedBox(
                    width: 176,
                    height: 226,
                    child: AlbumCard(album: shelf[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Your playlists" capped to a couple of rows, with an inline expander so a
/// large playlist collection doesn't swallow the page.
class _PlaylistSection extends StatefulWidget {
  const _PlaylistSection();

  static const _collapsedCount = 8;

  @override
  State<_PlaylistSection> createState() => _PlaylistSectionState();
}

class _PlaylistSectionState extends State<_PlaylistSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<LibraryController>().playlists;
    final overflowing = playlists.length > _PlaylistSection._collapsedCount;
    final visible = _expanded || !overflowing
        ? playlists
        : playlists.sublist(0, _PlaylistSection._collapsedCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionHeader('Your playlists'),
            const Spacer(),
            if (overflowing)
              _SectionAction(
                label: _expanded ? 'Show less' : 'Show all ${playlists.length}',
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _PlaylistRow(playlists: visible),
      ],
    );
  }
}

/// The full album library as a responsive grid — the "Show all" target of the
/// home view's Albums shelf. Lazily built, so large libraries stay smooth.
class AlbumsView extends StatelessWidget {
  const AlbumsView({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final albums = library.filteredAlbums;
    final genre = library.genreFilter;
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 24.0;
        const gap = 8.0;
        const target = 180.0;
        final width = constraints.maxWidth - padding * 2;
        final count = (width / target).floor().clamp(1, 8);
        final tileWidth = (width - ((count - 1) * gap)) / count;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(padding, padding, padding, 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Albums',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${albums.length} '
                      '${albums.length == 1 ? 'album' : 'albums'} '
                      '${genre == null ? 'in your library' : 'in '
                          '${musicDiscoveryTagLabel(genre)}'}',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const _GenreFilterBar(),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(padding, 0, padding, 32),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  mainAxisExtent: tileWidth + 70,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => AlbumCard(album: albums[i]),
                  childCount: albums.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Genre facets for [AlbumsView]. Renders nothing when the library carries no
/// usable genre tags, so a thinly-tagged library gets no dead chrome.
class _GenreFilterBar extends StatefulWidget {
  const _GenreFilterBar();

  @override
  State<_GenreFilterBar> createState() => _GenreFilterBarState();
}

class _GenreFilterBarState extends State<_GenreFilterBar> {
  /// Roughly two rows at a typical window width. A richly tagged library runs
  /// to 50+ facets, most of them one album deep.
  static const _collapsedLimit = 12;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final genres = library.genreFacets;
    if (genres.isEmpty) return const SizedBox.shrink();
    final selected = library.genreFilter;
    final visible = visibleGenreFacets(
      genres,
      selected,
      limit: _collapsedLimit,
      expanded: _expanded,
    );
    final hidden = genres.length - _collapsedLimit;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _GenreChip(
            label: 'All',
            selected: selected == null,
            onTap: () => library.setGenreFilter(null),
          ),
          for (final genre in visible)
            _GenreChip(
              label: '${musicDiscoveryTagLabel(genre)} '
                  '(${library.genreAlbumCount(genre)})',
              selected: selected == genre,
              // Tapping the active facet clears it, so the filter can be
              // undone without hunting for the "All" chip.
              onTap: () =>
                  library.setGenreFilter(selected == genre ? null : genre),
            ),
          if (hidden > 0)
            _GenreChip(
              label: _expanded ? 'Show less' : '+$hidden more',
              selected: false,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Material(
      color: selected ? accent : context.colors.surfaceHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? Theme.of(context).colorScheme.onSecondary
                  : context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.album});
  final Album album;

  @override
  Widget build(BuildContext context) {
    final nav = context.read<PlayerNavigator>();
    final client = context.read<ConnectionController>().client;
    final audio = context.watch<AudioController>();
    final playing = audio.sourceId == AudioController.albumSource(album.id);
    final animating = playing && audio.isPlaying;
    final unavailable =
        collectionUnavailableOffline(context, albumId: album.id);
    final genres = genreDetail(
      context.watch<LibraryController>().albumGenres(album.id),
    );

    final card = RecordTile(
      cover: (size) => Artwork(
        client: client,
        albumId: album.id,
        thumbnail: false,
        size: size,
        iconScale: 0.35,
      ),
      title: album.title,
      subtitle: ArtistLink(name: album.artist),
      playing: playing,
      animating: animating,
      unavailable: unavailable,
      onOpen: () => nav.openAlbum(album.id),
      onPlay: () => playAlbum(context, album.id),
      onSecondaryTapDown: (details) => showCollectionContextMenu(
        context,
        details.globalPosition,
        album: album,
      ),
    );

    // Genre rides on a tooltip rather than a third line of text: the grid's
    // tile extent is fixed, and untagged albums would otherwise leave a gap.
    if (genres == null) return card;
    return Tooltip(
      message: genres,
      waitDuration: const Duration(milliseconds: 400),
      child: card,
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlists});
  final List<PlaylistSummary> playlists;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final count = (constraints.maxWidth / 260).floor().clamp(1, 4);
        final width = (constraints.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final playlist in playlists)
              _PlaylistCard(playlist: playlist, width: width),
          ],
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.width});
  final PlaylistSummary playlist;
  final double width;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final accent = Theme.of(context).colorScheme.secondary;
    final playing =
        audio.sourceId == AudioController.playlistSource(playlist.id);
    final animating = playing && audio.isPlaying;
    final unavailable = collectionUnavailableOffline(
      context,
      songIds: playlist.songIds,
    );
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hover) => GestureDetector(
        onTap: () => context.read<PlayerNavigator>().openPlaylist(playlist.id),
        onSecondaryTapDown: (details) => showCollectionContextMenu(
          context,
          details.globalPosition,
          playlist: playlist,
        ),
        child: Opacity(
          opacity: unavailable ? 0.4 : 1,
          child: HoverSurface(
            active: hover,
            base: Colors.transparent,
            highlight: context.colors.surfaceHover,
            borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
            width: width,
            child: Row(
              children: [
                PlaylistArtwork(
                  playlist: playlist,
                  size: 56,
                  borderRadius: PlayerTheme.coverRadius,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PlayerTheme.heading(15,
                        color: context.colors.textPrimary),
                  ),
                ),
                if (hover)
                  IconButton(
                    tooltip: 'Play playlist',
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: () => playPlaylist(context, playlist),
                  )
                else if (playing)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: PlayingBars(
                      playing: animating,
                      color: accent,
                      size: 18,
                    ),
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album_outlined,
                size: 64, color: context.colors.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'Your library is empty',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              error ??
                  'Once your music folder has been scanned, your albums and '
                      'playlists will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => context.read<LibraryController>().load(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh library'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCuratedLibrary extends StatelessWidget {
  const _EmptyCuratedLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 64,
              color: context.colors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your curated library is empty',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick artists, albums, server playlists, or songs to include in '
              'your personal library, or switch to Include Everything.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => showPlayerLibraryCurationDialog(context),
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Curate My Library…'),
                ),
                OutlinedButton(
                  onPressed: () => context
                      .read<LibraryController>()
                      .completeCurationOnboardingFull(),
                  child: const Text('Include Everything'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
