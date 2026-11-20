import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/lyrics_controller.dart';
import '../services/player_navigator.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';
import 'album_link.dart';
import 'artist_credit_links.dart';
import 'artwork.dart';
import 'context_menu.dart';
import 'liked_song_button.dart';
import 'now_playing_full_view.dart';
import 'playback_helpers.dart';
import 'track_title_link.dart';

/// The top of the home page: the record on the platter, set large — its
/// cover and its title in display type. With nothing playing it offers a
/// way in instead.
class HomeNowPlaying extends StatelessWidget {
  const HomeNowPlaying({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final track = audio.currentTrack;
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final titleSize = constraints.maxWidth >= 1000
            ? 88.0
            : wide
                ? 68.0
                : 52.0;

        if (track == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nothing playing',
                  style: PlayerTheme.display(titleSize,
                      color: colors.textPrimary)),
              const SizedBox(height: 14),
              Text(
                'Pick a record below, or let Ariami choose one.',
                style: TextStyle(fontSize: 16, color: colors.textSecondary),
              ),
              const SizedBox(height: 22),
              const SurpriseMeButton(),
            ],
          );
        }

        final client = context.read<ConnectionController>().client;
        final hasLyrics = context
            .select<LyricsController?, bool>((c) => c?.hasLyrics ?? false);
        final coverSize =
            wide ? (constraints.maxWidth * 0.26).clamp(200.0, 288.0) : 160.0;

        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              audio.isPlaying ? 'Playing' : 'Paused',
              style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: Motion.medium,
              switchInCurve: Motion.standard,
              transitionBuilder: Motion.fadeSlideUp,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.bottomLeft,
                children: [...previous, if (current != null) current],
              ),
              child: TrackTitleLink(
                key: ValueKey(track.id),
                title: track.title,
                albumId: track.albumId,
                maxLines: 3,
                style:
                    PlayerTheme.display(titleSize, color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: 18),
            ArtistCreditLinks(
              name: track.artist,
              maxLines: 1,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
            if (track.albumTitle != null) ...[
              const SizedBox(height: 2),
              AlbumLink(
                title: track.albumTitle!,
                albumId: track.albumId,
                style: TextStyle(fontSize: 15, color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (track.albumId != null)
                  OutlinedButton(
                    onPressed: () => context
                        .read<PlayerNavigator>()
                        .openAlbum(track.albumId!),
                    child: const Text('Open album'),
                  ),
                if (hasLyrics)
                  OutlinedButton(
                    onPressed: () => _showLyrics(context),
                    child: const Text('Lyrics'),
                  ),
                LikedSongButton(track: track, iconSize: 22),
                const SurpriseMeButton(quiet: true),
              ],
            ),
          ],
        );

        final cover = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => showFullNowPlaying(context),
            child: Tooltip(
              message: 'Open full screen',
              waitDuration: const Duration(milliseconds: 600),
              child: Artwork(
                client: client,
                albumId: track.albumId,
                songId: track.albumId == null ? track.id : null,
                thumbnail: false,
                size: coverSize,
              ),
            ),
          ),
        );

        // Right-click anywhere on the record for the song's menu.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) =>
              showTrackContextMenu(context, details.globalPosition, track),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    cover,
                    const SizedBox(width: 40),
                    Expanded(child: details),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [cover, const SizedBox(height: 24), details],
                ),
        );
      },
    );
  }

  void _showLyrics(BuildContext context) {
    context.read<LyricsController?>()?.setLyricsPreferred(true);
    final nav = context.read<PlayerNavigator>();
    if (!nav.rightPanelOpen) nav.toggleRightPanel();
  }
}

/// Plays a random album or playlist from the library. The first press
/// explains itself once. [quiet] renders it as a text action beside others.
class SurpriseMeButton extends StatelessWidget {
  const SurpriseMeButton({super.key, this.quiet = false});

  final bool quiet;

  static const _introSeenKey = 'surprise_me_intro_seen';

  @override
  Widget build(BuildContext context) {
    const label = Text('Surprise me');
    return quiet
        ? TextButton(
            style: TextButton.styleFrom(
                foregroundColor: context.colors.textSecondary),
            onPressed: () => _onTap(context),
            child: label,
          )
        : OutlinedButton(onPressed: () => _onTap(context), child: label);
  }

  Future<void> _onTap(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_introSeenKey) ?? false)) {
      await prefs.setBool(_introSeenKey, true);
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Surprise me'),
          content: const SizedBox(
            width: 380,
            child: Text(
              'Plays a random album or playlist from your library, for when '
              'you can\'t decide. This note only shows once.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Surprise me'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    if (!context.mounted) return;
    _surprise(context);
  }

  void _surprise(BuildContext context) {
    final library = context.read<LibraryController>();
    final albums = library.albums;
    final playlists =
        library.playlists.where((p) => p.songIds.isNotEmpty).toList();
    final pool = albums.length + playlists.length;
    if (pool == 0) return;
    final index = Random().nextInt(pool);
    final nav = context.read<PlayerNavigator>();
    if (index < albums.length) {
      final album = albums[index];
      nav.openAlbum(album.id);
      playAlbum(context, album.id);
    } else {
      final playlist = playlists[index - albums.length];
      nav.openPlaylist(playlist.id);
      playPlaylist(context, playlist);
    }
  }
}
