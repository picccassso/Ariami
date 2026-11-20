import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/listening_stats_controller.dart';
import '../services/player_navigator.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'context_menu.dart';
import 'downloaded_badge.dart';
import 'hover_builder.dart';
import 'playback_helpers.dart';
import 'playlist_artwork.dart';
import 'record_tile.dart';
import 'scroll_rail.dart';

/// "Recently played": a horizontal rail of recently played albums/playlists.
/// Renders nothing until there's history. Includes its own section header so
/// the home view stays clean when empty.
class JumpBackInRow extends StatelessWidget {
  const JumpBackInRow({super.key});

  static const _maxCards = 8;

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<ListeningStatsController>();
    final library = context.watch<LibraryController>();

    final cards = <Widget>[];
    for (final source in stats.recentSources) {
      if (source.startsWith('album:')) {
        final album = _albumById(library, source.substring('album:'.length));
        if (album != null) cards.add(_JumpBackCard.album(album));
      } else if (source.startsWith('playlist:')) {
        final playlist =
            _playlistById(library, source.substring('playlist:'.length));
        if (playlist != null) cards.add(_JumpBackCard.playlist(playlist));
      }
      if (cards.length >= JumpBackInRow._maxCards) break;
    }
    if (cards.isEmpty) return const SizedBox.shrink();

    // One region wraps header + rail so the "Clear all" affordance and the
    // scrubber both fade in together while the pointer is anywhere over the
    // section.
    return HoverBuilder(
      builder: (context, hover) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Recently played',
                style:
                    PlayerTheme.heading(22, color: context.colors.textPrimary),
              ),
              const Spacer(),
              AnimatedOpacity(
                duration: Motion.fast,
                opacity: hover ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !hover,
                  child: TextButton(
                    onPressed: () => context
                        .read<ListeningStatsController>()
                        .clearRecentSources(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: context.colors.textSecondary,
                    ),
                    child: const Text(
                      'Clear all',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ScrollRail(
            revealScrubber: hover,
            child: Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 20),
                  cards[i],
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  static Album? _albumById(LibraryController library, String id) {
    for (final album in library.albums) {
      if (album.id == id) return album;
    }
    return null;
  }

  static PlaylistSummary? _playlistById(LibraryController library, String id) {
    for (final playlist in library.playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }
}

class _JumpBackCard extends StatefulWidget {
  const _JumpBackCard.album(Album this.album) : playlist = null;
  const _JumpBackCard.playlist(PlaylistSummary this.playlist) : album = null;

  final Album? album;
  final PlaylistSummary? playlist;

  @override
  State<_JumpBackCard> createState() => _JumpBackCardState();
}

class _JumpBackCardState extends State<_JumpBackCard> {
  static const _artSize = 160.0;

  @override
  Widget build(BuildContext context) {
    final nav = context.read<PlayerNavigator>();
    final album = widget.album;
    final playlist = widget.playlist;
    final title = album?.title ?? playlist!.name;
    final subtitle = album != null ? album.artist : 'Playlist';
    final sourceKey =
        album != null ? 'album:${album.id}' : 'playlist:${playlist!.id}';
    final unavailable = collectionUnavailableOffline(
      context,
      albumId: album?.id,
      songIds: album == null ? playlist!.songIds : null,
    );

    return SizedBox(
      width: _artSize,
      height: _artSize + 48,
      child: RecordTile(
        cover: (size) => album != null
            ? Artwork(
                client: context.read<ConnectionController>().client,
                albumId: album.id,
                thumbnail: false,
                size: size,
                iconScale: 0.35,
              )
            : PlaylistArtwork(
                playlist: playlist!,
                size: size,
                borderRadius: PlayerTheme.coverRadius,
              ),
        title: title,
        subtitle: Text(subtitle),
        unavailable: unavailable,
        onOpen: () => album != null
            ? nav.openAlbum(album.id)
            : nav.openPlaylist(playlist!.id),
        onPlay: () => album != null
            ? playAlbum(context, album.id)
            : playPlaylist(context, playlist!),
        onSecondaryTapDown: (details) => showCollectionContextMenu(
          context,
          details.globalPosition,
          album: album,
          playlist: playlist,
        ),
        // Soft dismiss from the recents row: it returns if the collection is
        // played again.
        corner: Tooltip(
          message: 'Remove from recently played',
          child: Material(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
              onTap: () => context
                  .read<ListeningStatsController>()
                  .removeRecentSource(sourceKey),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
