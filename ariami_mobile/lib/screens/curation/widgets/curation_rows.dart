import 'dart:io';

import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:ariami_core/services/stats/credited_artist_splitter.dart';
import 'package:flutter/material.dart';

import '../../../models/api_models.dart';
import '../../../services/api/connection_service.dart';
import '../../../services/artist_image_service.dart';
import '../../../services/playlist_service.dart';
import '../../../utils/artwork_url.dart';
import '../../../utils/constants.dart';
import '../../../widgets/common/cached_artwork.dart';
import '../../../widgets/common/song_artwork.dart';
import '../../../widgets/library/playlist_artwork.dart';

/// Height used across all top-level curation list rows so alphabetical scroll
/// jumping stays exact.
const double kCurationRowHeight = 64.0;

/// Tap-to-toggle circular check indicator styled in Ariami's ink-on-ground
/// palette, with a 44×44 touch target.
class CurationCheckCircle extends StatelessWidget {
  const CurationCheckCircle({
    super.key,
    required this.state,
    required this.onTap,
    this.semanticsLabel,
  });

  final CurationArtistSelectionState state;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isAll = state == CurationArtistSelectionState.all;
    final isPartial = state == CurationArtistSelectionState.partial;

    return Semantics(
      button: true,
      checked: isAll,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isAll
                    ? colors.textPrimary
                    : isPartial
                        ? colors.surfaceHigh
                        : Colors.transparent,
                border: Border.all(
                  color: isAll || isPartial
                      ? colors.textPrimary
                      : colors.textSecondary.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: isAll
                  ? Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: colors.base,
                    )
                  : isPartial
                      ? Icon(
                          Icons.remove_rounded,
                          size: 14,
                          color: colors.textPrimary,
                        )
                      : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular 44×44 artist thumbnail: prefers custom artist image, falls back to
/// the artist's album cover, then a credited song cover, then an initial monogram.
class CurationArtistArtwork extends StatelessWidget {
  const CurationArtistArtwork({
    super.key,
    required this.artistName,
    this.fallbackAlbum,
    this.fallbackAlbumId,
    this.fallbackAlbumCoverArt,
    this.fallbackSongId,
    this.size = 44,
  });

  final String artistName;
  final CurationCatalogAlbum? fallbackAlbum;
  final String? fallbackAlbumId;
  final String? fallbackAlbumCoverArt;
  final String? fallbackSongId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final apiClient = ConnectionService().apiClient;
    final trimmed = artistName.trim();
    final initial = trimmed.isNotEmpty ? trimmed.substring(0, 1).toUpperCase() : '?';

    final monogram = Container(
      width: size,
      height: size,
      color: colors.surfaceHigh,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTheme.heading(size * 0.4, color: colors.textSecondary),
      ),
    );

    final resolvedSongId = fallbackSongId?.trim();
    final songFallback = (resolvedSongId != null && resolvedSongId.isNotEmpty)
        ? CachedArtwork(
            key: ValueKey('curation-artist-song-$resolvedSongId'),
            albumId: 'song_$resolvedSongId',
            artworkUrl: '/api/song-artwork/${Uri.encodeComponent(resolvedSongId)}',
            width: size,
            height: size,
            fit: BoxFit.cover,
            sizeHint: ArtworkSizeHint.thumbnail,
            fallback: monogram,
          )
        : monogram;

    final resolvedAlbumId = (fallbackAlbumId ?? fallbackAlbum?.id)?.trim();
    final albumFallback = (resolvedAlbumId != null && resolvedAlbumId.isNotEmpty)
        ? CachedArtwork(
            key: ValueKey('curation-artist-album-$resolvedAlbumId'),
            albumId: resolvedAlbumId,
            artworkUrl: resolveAlbumArtworkUrl(
              albumId: resolvedAlbumId,
              coverArt: fallbackAlbumCoverArt,
            ),
            width: size,
            height: size,
            fit: BoxFit.cover,
            sizeHint: ArtworkSizeHint.thumbnail,
            fallback: songFallback,
          )
        : songFallback;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: ListenableBuilder(
          listenable: ArtistImageService(),
          builder: (context, _) {
            final customVersion =
                ArtistImageService().artistImageVersion(artistName);
            if (customVersion != null && apiClient != null) {
              final safeKey =
                  Uri.encodeComponent(normalizeArtistKey(artistName));
              return CachedArtwork(
                key: ValueKey(
                  'curation-artist-custom-${safeKey}_v$customVersion',
                ),
                albumId: 'artist_${safeKey}_v$customVersion',
                artworkUrl: apiClient.artistImageUrl(
                  artistName,
                  version: customVersion,
                ),
                width: size,
                height: size,
                fit: BoxFit.cover,
                sizeHint: ArtworkSizeHint.thumbnail,
                fallback: albumFallback,
              );
            }
            return albumFallback;
          },
        ),
      ),
    );
  }
}

/// Crisp square 44×44 album cover thumbnail.
class CurationAlbumArtwork extends StatelessWidget {
  const CurationAlbumArtwork({
    super.key,
    required this.albumId,
    this.coverArt,
    this.size = 44,
  });

  final String albumId;
  final String? coverArt;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.coverRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: CachedArtwork(
          albumId: albumId,
          artworkUrl: resolveAlbumArtworkUrl(
            albumId: albumId,
            coverArt: coverArt,
          ),
          width: size,
          height: size,
          fit: BoxFit.cover,
          sizeHint: ArtworkSizeHint.thumbnail,
          fallbackIconSize: size * 0.5,
        ),
      ),
    );
  }
}

/// Compact 64 px artist row with artwork, selection summary, drill chevron,
/// and independent check circle.
class CurationArtistTile extends StatelessWidget {
  const CurationArtistTile({
    super.key,
    required this.group,
    required this.selectionState,
    required this.includedCount,
    required this.onTap,
    required this.onToggleWhole,
    this.fallbackAlbumId,
    this.fallbackAlbumCoverArt,
    this.fallbackSongId,
    this.isWideSelected = false,
    this.showChevron = true,
  });

  final CurationArtistGroup group;
  final CurationArtistSelectionState selectionState;
  final int includedCount;
  final VoidCallback onTap;
  final VoidCallback onToggleWhole;
  final String? fallbackAlbumId;
  final String? fallbackAlbumCoverArt;
  final String? fallbackSongId;
  final bool isWideSelected;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final albumCount = group.albums.length;
    final singleCount = group.standaloneSongs.length;
    final parts = <String>[
      if (albumCount > 0) '$albumCount ${albumCount == 1 ? 'album' : 'albums'}',
      if (singleCount > 0)
        '$singleCount ${singleCount == 1 ? 'single' : 'singles'}',
      if (group.totalItems > 0) '$includedCount/${group.totalItems} included',
    ];

    return _CurationRowShell(
      highlighted: isWideSelected,
      onTap: onTap,
      leading: CurationArtistArtwork(
        artistName: group.displayName,
        fallbackAlbum: group.albums.firstOrNull,
        fallbackAlbumId: fallbackAlbumId,
        fallbackAlbumCoverArt: fallbackAlbumCoverArt,
        fallbackSongId:
            fallbackSongId ?? group.standaloneSongs.firstOrNull?.id,
      ),
      title: group.displayName,
      subtitle: parts.join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showChevron)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.textSecondary,
              ),
            ),
          CurationCheckCircle(
            state: selectionState,
            onTap: onToggleWhole,
            semanticsLabel: 'Toggle ${group.displayName}',
          ),
        ],
      ),
    );
  }
}

/// Compact 64 px album row with cover art, artist/song count, track-picker
/// button, and check circle.
class CurationAlbumTile extends StatelessWidget {
  const CurationAlbumTile({
    super.key,
    required this.album,
    required this.selectionState,
    required this.includedTrackCount,
    required this.totalTrackCount,
    required this.onToggle,
    this.onOpenTracks,
  });

  final AlbumModel album;
  final CurationArtistSelectionState selectionState;
  final int includedTrackCount;
  final int totalTrackCount;
  final VoidCallback onToggle;
  final VoidCallback? onOpenTracks;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trackLabel = totalTrackCount > 0 &&
            selectionState == CurationArtistSelectionState.partial
        ? '$includedTrackCount/$totalTrackCount tracks'
        : '${album.songCount} ${album.songCount == 1 ? 'song' : 'songs'}';

    return _CurationRowShell(
      onTap: onToggle,
      leading: CurationAlbumArtwork(
        albumId: album.id,
        coverArt: album.coverArt,
      ),
      title: album.title,
      subtitle: '${album.artist} · $trackLabel',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onOpenTracks != null)
            IconButton(
              icon: Icon(
                Icons.format_list_bulleted_rounded,
                size: 18,
                color: colors.textSecondary,
              ),
              tooltip: 'Pick individual tracks',
              visualDensity: VisualDensity.compact,
              onPressed: onOpenTracks,
            ),
          CurationCheckCircle(
            state: selectionState,
            onTap: onToggle,
            semanticsLabel: 'Toggle ${album.title}',
          ),
        ],
      ),
    );
  }
}

/// Compact 64 px server playlist row with collage artwork and check circle.
class CurationPlaylistTile extends StatelessWidget {
  const CurationPlaylistTile({
    super.key,
    required this.playlist,
    required this.albumIds,
    required this.included,
    required this.onToggle,
  });

  final CurationCatalogPlaylist playlist;
  final List<String> albumIds;
  final bool included;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final playlistService = PlaylistService();
    return _CurationRowShell(
      onTap: onToggle,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.coverRadius),
        child: SizedBox(
          width: 44,
          height: 44,
          child: ListenableBuilder(
            listenable: playlistService,
            builder: (context, _) {
              final customImagePath =
                  playlistService.customImagePathForServerPlaylist(playlist.id);
              final customImageExists = customImagePath != null &&
                  File(customImagePath).existsSync();
              final artwork = PlaylistArtwork(
                playlistName: playlist.name,
                customImagePath: customImagePath,
                customImageExists: customImageExists,
                albumIds: albumIds,
                isLikedSongs: false,
                iconSize: 20,
                decodeWidth: 44,
              );
              if (customImageExists) return artwork;

              final imageVersion =
                  playlistService.serverPlaylistImageVersion(playlist.id);
              if (imageVersion == null) return artwork;

              final safeId = Uri.encodeComponent(playlist.id);
              return CachedArtwork(
                key: ValueKey('curation-playlist-custom-${safeId}_v$imageVersion'),
                albumId: 'playlist_${safeId}_v$imageVersion',
                artworkUrl: '/api/playlists/$safeId/image?v=$imageVersion',
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                sizeHint: ArtworkSizeHint.thumbnail,
                fallback: artwork,
              );
            },
          ),
        ),
      ),
      title: playlist.name,
      subtitle:
          '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
      trailing: CurationCheckCircle(
        state: included
            ? CurationArtistSelectionState.all
            : CurationArtistSelectionState.none,
        onTap: onToggle,
        semanticsLabel: 'Toggle ${playlist.name}',
      ),
    );
  }
}

/// Compact 64 px song row with song/album artwork and check circle.
class CurationSongTile extends StatelessWidget {
  const CurationSongTile({
    super.key,
    required this.song,
    required this.albumTitle,
    required this.included,
    required this.onToggle,
  });

  final SongModel song;
  final String? albumTitle;
  final bool included;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        albumTitle != null && albumTitle!.isNotEmpty
            ? '${song.artist} · $albumTitle'
            : song.artist;

    return _CurationRowShell(
      onTap: onToggle,
      leading: SongArtwork(
        song: song,
        size: 44,
        borderRadius: BorderRadius.circular(AppTheme.coverRadius),
      ),
      title: song.title,
      subtitle: subtitle,
      trailing: CurationCheckCircle(
        state: included
            ? CurationArtistSelectionState.all
            : CurationArtistSelectionState.none,
        onTap: onToggle,
        semanticsLabel: 'Toggle ${song.title}',
      ),
    );
  }
}

class _CurationRowShell extends StatelessWidget {
  const _CurationRowShell({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.highlighted = false,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: kCurationRowHeight,
      child: Material(
        color: highlighted ? colors.surfaceHover : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.border.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                          fontFeatures: AppTheme.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
