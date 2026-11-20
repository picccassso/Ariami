import 'package:ariami_core/models/image_limits.dart';
import 'package:ariami_core/models/listening_stats_models.dart'
    show ListeningSongRollup;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/listening_stats_controller.dart';
import '../services/player_api_client.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'artwork_preview.dart';
import 'browse_view.dart' show AlbumCard;
import 'collection_play_buttons.dart';
import 'context_menu.dart';
import 'detail_header.dart';
import 'downloaded_badge.dart';
import 'hover_builder.dart';
import 'playlist_artwork.dart';
import 'playlist_play_fab.dart';
import 'playing_indicator.dart';
import 'track_list.dart';

enum _ArtistPhotoAction { change, remove }

/// Artist page: header with play/shuffle, the artist's top songs, their
/// albums, compilations they appear on, and the playlists their songs appear
/// on. Everything is derived from the in-memory library — no fetch.
class ArtistDetailView extends StatelessWidget {
  const ArtistDetailView({super.key, required this.artistName});
  final String artistName;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final stats = context.watch<ListeningStatsController>();
    final albums = library.artistAlbums(artistName);
    final playlists = library.playlistsWithArtist(artistName);
    final tracks = library.artistTracks(artistName);
    final appearsOn = library.artistAppearsOn(artistName);
    final topTracks = _topTracks(tracks, stats.snapshot.songs);
    final artworkAlbum = _firstAlbumWithArtwork([...albums, ...appearsOn]);
    final artworkTrack = tracks.isEmpty ? null : tracks.first;

    if (albums.isEmpty && playlists.isEmpty && tracks.isEmpty) {
      return Center(
        child: Text(
          'This artist isn\'t in your library.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }

    final client = context.read<ConnectionController>().client;
    final customImageVersion = library.artistImageVersion(artistName);
    final customImageUrl = customImageVersion != null && client != null
        ? client.artistImageUrl(artistName, version: customImageVersion)
        : null;

    final headerArtwork = _ArtistHeaderArtwork(
      artistName: artistName,
      client: client,
      artworkAlbum: artworkAlbum,
      artworkTrack: artworkTrack,
      customImageUrl: customImageUrl,
      customImageVersion: customImageVersion,
    );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DetailHeader(
          kindLabel: 'Artist',
          title: artistName,
          subtitle: _plural(albums.length, 'album'),
          metaLine: '${_plural(playlists.length, 'playlist')}, '
              '${_plural(tracks.length, 'song')}',
          artwork: headerArtwork,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 16),
          child: Row(
            children: [
              CollectionPlayButton(
                tracks: tracks,
                sourceId: AudioController.artistSource(artistName),
                noun: 'artist',
              ),
              const SizedBox(width: 12),
              CollectionShuffleButton(
                tracks: tracks,
                sourceId: AudioController.artistSource(artistName),
                noun: 'artist',
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_ArtistPhotoAction>(
                tooltip: 'Artist photo options',
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: context.colors.popover,
                onSelected: (action) {
                  if (action == _ArtistPhotoAction.change) {
                    pickAndUploadArtistPhoto(context, artistName);
                  } else if (action == _ArtistPhotoAction.remove) {
                    removeArtistPhoto(context, artistName);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _ArtistPhotoAction.change,
                    child: Row(
                      children: [
                        Icon(Icons.photo_camera_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Change photo'),
                      ],
                    ),
                  ),
                  if (customImageVersion != null)
                    const PopupMenuItem(
                      value: _ArtistPhotoAction.remove,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Remove photo'),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (topTracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Text(
              'Top songs',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (var i = 0; i < topTracks.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TrackRow(
                track: topTracks[i],
                context: topTracks,
                sourceId: AudioController.artistSource(artistName),
                index: i + 1,
                showGoToAlbum: true,
                linkTitleToAlbum: true,
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Albums',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (albums.isEmpty)
                _EmptySection(
                    message: 'No albums by this artist in your library.')
              else
                _TilesWrap(
                  tiles: [
                    for (final album in albums) AlbumCard(album: album),
                  ],
                ),
              if (appearsOn.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Appears on',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _TilesWrap(
                  tiles: [
                    for (final album in appearsOn) AlbumCard(album: album),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Playlists',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (playlists.isEmpty)
                _EmptySection(message: 'Not on any playlists yet.')
              else
                _TilesWrap(
                  tiles: [
                    for (final playlist in playlists)
                      _PlaylistTile(playlist: playlist),
                  ],
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  String _plural(int count, String noun) =>
      '$count $noun${count == 1 ? '' : 's'}';
}

Album? _firstAlbumWithArtwork(Iterable<Album> albums) {
  for (final album in albums) {
    if (album.coverArtPath?.trim().isNotEmpty == true) return album;
  }
  return null;
}

/// How many of an artist's songs the page lists — the full discography makes
/// the page one long list, so the section caps at the most-listened songs.
const int _topSongsLimit = 10;

/// Ranks [tracks] by listening stats and caps the list at [_topSongsLimit].
/// Unplayed songs keep their library order below the played ones, so the
/// section stays short but never empty.
List<Track> _topTracks(List<Track> tracks, List<ListeningSongRollup> rollups) {
  final plays = <String, ListeningSongRollup>{
    for (final rollup in rollups) rollup.songId: rollup,
  };
  final ranked = <({Track track, int plays, int listenedMs, int index})>[
    for (var i = 0; i < tracks.length; i++)
      (
        track: tracks[i],
        plays: plays[tracks[i].id]?.playCount ?? 0,
        listenedMs: plays[tracks[i].id]?.listenedMs ?? 0,
        index: i,
      ),
  ]..sort((a, b) {
      if (a.plays != b.plays) return b.plays.compareTo(a.plays);
      if (a.listenedMs != b.listenedMs) {
        return b.listenedMs.compareTo(a.listenedMs);
      }
      // The sort isn't stable, so the library order breaks ties explicitly.
      return a.index.compareTo(b.index);
    });
  return ranked.take(_topSongsLimit).map((entry) => entry.track).toList();
}

/// Responsive tile grid, mirroring [AlbumsView]'s sizing, so albums and
/// playlists sit side by side at the same size.
class _TilesWrap extends StatelessWidget {
  const _TilesWrap({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        const target = 180.0;
        final count = (constraints.maxWidth / target).floor().clamp(1, 8);
        final tileWidth = (constraints.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(width: tileWidth, height: tileWidth + 70, child: tile),
          ],
        );
      },
    );
  }
}

/// A playlist tile on the artist page, mirroring [AlbumCard]'s layout so the
/// two sections look the same: artwork, hover play button, name below.
class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist});
  final PlaylistSummary playlist;

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
        child: AnimatedScale(
          duration: Motion.fast,
          curve: Motion.standard,
          scale: hover ? 1.02 : 1.0,
          child: Opacity(
            opacity: unavailable ? 0.4 : 1,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hover ? context.colors.surfaceHover : Colors.transparent,
                borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, c) => PlaylistArtwork(
                              playlist: playlist,
                              size: c.maxWidth,
                              borderRadius: 10,
                            ),
                          ),
                        ),
                        if (playing)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: PlayingBars(
                                playing: animating,
                                color: accent,
                                size: 16,
                              ),
                            ),
                          ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: AnimatedSlide(
                            duration: Motion.medium,
                            curve: Motion.standard,
                            offset: hover ? Offset.zero : const Offset(0, 0.25),
                            child: AnimatedOpacity(
                              duration: Motion.fast,
                              opacity: hover ? 1 : 0,
                              child: PlaylistPlayFab(playlist: playlist),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: playing ? accent : context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.songCount} '
                    '${playlist.songCount == 1 ? 'song' : 'songs'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
    );
  }
}

/// Lets the user pick a JPEG/PNG/WebP photo and uploads it as [artistName]'s
/// custom image. The server syncs it to every signed-in client (mobile,
/// desktop, TV) through the account's artist-image store.
Future<void> pickAndUploadArtistPhoto(
  BuildContext context,
  String artistName,
) async {
  final library = context.read<LibraryController>();
  final readLocalFileBytes = maybeReadHost(context)?.readLocalFileBytes;
  final result = await FilePicker.pickFiles(
    dialogTitle: 'Choose artist photo',
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    withData: true,
  );
  final file = result?.files.firstOrNull;
  if (file == null) return;

  var bytes = file.bytes;
  if (bytes == null && file.path != null && readLocalFileBytes != null) {
    try {
      bytes = await readLocalFileBytes(file.path!);
    } catch (_) {
      bytes = null;
    }
  }
  if (!context.mounted) return;
  if (bytes == null || bytes.isEmpty) {
    _showToast(context, 'Could not read that file.');
    return;
  }
  if (bytes.length > kMaxUserImageBytes) {
    _showToast(context, 'Photo is too large (max 5 MB).');
    return;
  }
  final contentType = _sniffArtistImageContentType(bytes);
  if (contentType == null) {
    _showToast(context, 'Unsupported image format. Use JPEG, PNG or WebP.');
    return;
  }

  try {
    await library.setArtistImage(
      artistName,
      bytes: bytes,
      contentType: contentType,
    );
    if (context.mounted) _showToast(context, 'Artist photo updated');
  } catch (_) {
    if (context.mounted) _showToast(context, 'Could not upload the photo.');
  }
}

/// Removes [artistName]'s custom image from the account's image store,
/// reverting every client back to the album/song cover fallback.
Future<void> removeArtistPhoto(
  BuildContext context,
  String artistName,
) async {
  final library = context.read<LibraryController>();
  try {
    await library.removeArtistImage(artistName);
    if (context.mounted) _showToast(context, 'Artist photo removed');
  } catch (_) {
    if (context.mounted) _showToast(context, 'Could not remove the photo.');
  }
}

String? _sniffArtistImageContentType(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

void _showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ),
  );
}

class _ArtistHeaderArtwork extends StatelessWidget {
  const _ArtistHeaderArtwork({
    required this.artistName,
    required this.client,
    required this.artworkAlbum,
    required this.artworkTrack,
    required this.customImageUrl,
    required this.customImageVersion,
  });

  final String artistName;
  final PlayerApiClient? client;
  final Album? artworkAlbum;
  final Track? artworkTrack;
  final String? customImageUrl;
  final int? customImageVersion;

  @override
  Widget build(BuildContext context) {
    final client = this.client;
    final fallbackArtworkWidget = Artwork(
      key: const ValueKey('artist-header-artwork'),
      client: client,
      albumId: artworkAlbum?.id,
      songId: artworkTrack?.id,
      thumbnail: false,
      size: 200,
      borderRadius: 8,
      iconScale: 0.4,
    );

    final imageDisplay = customImageUrl != null && client != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(
              image: Artwork.cachedImage(
                customImageUrl!,
                client,
                cacheWidth:
                    (200 * MediaQuery.devicePixelRatioOf(context) * 2).round(),
              ),
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, _, __) => fallbackArtworkWidget,
            ),
          )
        : fallbackArtworkWidget;

    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hover) => GestureDetector(
        onTap: () => showArtworkPreview(
          context,
          client: client,
          albumId: artworkAlbum?.id,
          songId: artworkTrack?.id,
          imageUrl: customImageUrl,
        ),
        child: Stack(
          children: [
            imageDisplay,
            Positioned(
              right: 8,
              bottom: 8,
              child: AnimatedOpacity(
                opacity: hover ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: PopupMenuButton<_ArtistPhotoAction>(
                  tooltip: '',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: context.colors.popover,
                  onSelected: (action) {
                    if (action == _ArtistPhotoAction.change) {
                      pickAndUploadArtistPhoto(context, artistName);
                    } else if (action == _ArtistPhotoAction.remove) {
                      removeArtistPhoto(context, artistName);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _ArtistPhotoAction.change,
                      child: Row(
                        children: [
                          Icon(Icons.photo_camera_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Change photo'),
                        ],
                      ),
                    ),
                    if (customImageVersion != null)
                      const PopupMenuItem(
                        value: _ArtistPhotoAction.remove,
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Remove photo'),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
