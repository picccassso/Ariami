part of '../library_sidebar.dart';

/// Sidebar entry for an artist: an [_IndexRow] when expanded, a round
/// portrait in the collapsed rail — the only cue there that separates a
/// person from the record beside them.
class _ArtistTile extends StatelessWidget {
  const _ArtistTile({
    required this.artist,
    this.collapsed = false,
    this.selection = SidebarEntrySelection.none,
    this.quickJumpIndex,
    this.letter,
  });

  final LibraryArtistSummary artist;
  final bool collapsed;
  final SidebarEntrySelection selection;
  final int? quickJumpIndex;

  /// The index letter, set on the first entry under each letter.
  final String? letter;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final navigator = context.read<PlayerNavigator>();
    final client = context.read<ConnectionController>().client;
    final viewing = context.select<PlayerNavigator, bool>(
      (value) =>
          value.current.kind == PlayerViewKind.artist &&
          value.current.id == artist.name,
    );
    final sourceId = AudioController.artistSource(artist.name);
    final playing = audio.sourceId == sourceId;
    final animating = playing && audio.isPlaying;
    final active = playing || viewing;

    // Checks for custom artist photo in the account's image store; otherwise
    // borrows a cover the artist is on (see [LibraryArtistSummary]) and falls
    // back to a person glyph.
    final size = collapsed ? 46.0 : _IndexRow.artSize;
    final library = context.watch<LibraryController>();
    final customImageVersion = library.artistImageVersion(artist.name);
    final customImageUrl = customImageVersion != null && client != null
        ? client.artistImageUrl(artist.name, version: customImageVersion)
        : null;

    final fallbackArt = Artwork(
      client: client,
      albumId: artist.artworkAlbumId,
      songId: artist.artworkSongId,
      size: size,
      borderRadius: size / 2,
      iconScale: 0.52,
      placeholderIcon: Icons.person_rounded,
    );

    final art = customImageUrl != null && client != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: Image(
              image: Artwork.cachedImage(
                customImageUrl,
                client,
                cacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context) * 2).round(),
              ),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => fallbackArt,
            ),
          )
        : fallbackArt;
    void open() {
      if (selection.claimTap()) return;
      navigator.openArtist(artist.name);
    }

    if (collapsed) {
      return _CollapsedTile(
        tooltip: artist.name,
        onTap: open,
        onSecondaryTapDown: (details) =>
            _showArtistMenu(context, details.globalPosition, artist.name),
        child: _PinnedArtwork(
          artwork: art,
          pinned: false,
          playing: playing,
          animating: animating,
          selected: selection.selected,
        ),
      );
    }

    return _IndexRow(
      title: artist.name,
      art: art,
      subtitle: artist.albumCount == 0
          ? null
          : '${artist.albumCount} ${artist.albumCount == 1 ? 'album' : 'albums'}',
      letter: letter,
      active: active,
      playing: playing,
      animating: animating,
      selection: selection,
      quickJumpIndex: quickJumpIndex,
      sourceId: sourceId,
      onStart: () => playArtist(context, artist.name),
      onTap: open,
      onSecondaryTapDown: (details) =>
          _showArtistMenu(context, details.globalPosition, artist.name),
    );
  }
}
