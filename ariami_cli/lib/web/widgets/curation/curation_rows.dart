import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';
import 'web_artwork.dart';

/// Height used across all top-level curation list rows so alphabetical scroll
/// jumping stays exact.
const double kCurationRowHeight = 64.0;

const List<FontFeature> _tabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

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
    final isAll = state == CurationArtistSelectionState.all;
    final isPartial = state == CurationArtistSelectionState.partial;

    return Semantics(
      button: true,
      checked: isAll,
      label: semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
                      ? AppTheme.textPrimary
                      : isPartial
                          ? AppTheme.surfaceRaised
                          : Colors.transparent,
                  border: Border.all(
                    color: isAll || isPartial
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
                child: isAll
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppTheme.base,
                      )
                    : isPartial
                        ? const Icon(
                            Icons.remove_rounded,
                            size: 14,
                            color: AppTheme.textPrimary,
                          )
                        : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular artist thumbnail: prefers the artist's album cover, falls back to
/// a credited song cover, then an initial monogram.
class CurationArtistArtwork extends StatelessWidget {
  const CurationArtistArtwork({
    super.key,
    required this.artistName,
    this.fallbackAlbum,
    this.fallbackAlbumId,
    this.fallbackSongId,
    this.artworkClient,
    this.size = 44,
  });

  final String artistName;
  final CurationCatalogAlbum? fallbackAlbum;
  final String? fallbackAlbumId;
  final String? fallbackSongId;
  final WebApiClient? artworkClient;
  final double size;

  int _cacheWidth(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    return (size * dpr * 2).clamp(96, 512).round();
  }

  Widget _buildImageLayer(
    BuildContext context, {
    required String url,
    required WebApiClient client,
    required Widget fallback,
  }) {
    return Image(
      image: ResizeImage.resizeIfNeeded(
        _cacheWidth(context),
        null,
        WebArtworkImageProvider(url, client: client),
      ),
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = artistName.trim();
    final initial =
        trimmed.isNotEmpty ? trimmed.substring(0, 1).toUpperCase() : '?';

    final monogram = Container(
      width: size,
      height: size,
      color: AppTheme.surfaceRaised,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: AppTheme.headingFamily,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          height: 1.15,
          color: AppTheme.textSecondary,
        ),
      ),
    );

    final client = artworkClient;
    final resolvedAlbumId = fallbackAlbumId ?? fallbackAlbum?.id;
    final resolvedSongId = fallbackSongId;

    Widget artworkLayer = monogram;
    if (client != null &&
        resolvedSongId != null &&
        resolvedSongId.trim().isNotEmpty) {
      artworkLayer = _buildImageLayer(
        context,
        url: client.songArtworkUrl(resolvedSongId, thumbnail: true),
        client: client,
        fallback: monogram,
      );
    }
    if (client != null &&
        resolvedAlbumId != null &&
        resolvedAlbumId.trim().isNotEmpty) {
      artworkLayer = _buildImageLayer(
        context,
        url: client.albumArtworkUrl(resolvedAlbumId, thumbnail: true),
        client: client,
        fallback: artworkLayer,
      );
    }

    final child = identical(artworkLayer, monogram)
        ? monogram
        : Stack(
            fit: StackFit.expand,
            children: [
              monogram,
              artworkLayer,
            ],
          );

    return ClipOval(
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

/// Crisp square album cover thumbnail.
class CurationAlbumArtwork extends StatelessWidget {
  const CurationAlbumArtwork({
    super.key,
    required this.albumId,
    this.artworkClient,
    this.size = 44,
  });

  final String albumId;
  final WebApiClient? artworkClient;
  final double size;

  @override
  Widget build(BuildContext context) {
    return WebArtwork(
      client: artworkClient,
      albumId: albumId,
      size: size,
      borderRadius: AppTheme.radiusSmall,
      placeholderIcon: Icons.album_rounded,
      deferDuringScroll: true,
    );
  }
}

/// Playlist thumbnail: 2×2 album cover mosaic (or single album cover / gradient
/// fallback).
class CurationPlaylistArtwork extends StatelessWidget {
  const CurationPlaylistArtwork({
    super.key,
    required this.playlistId,
    required this.playlistName,
    this.albumIds = const <String>[],
    this.artworkClient,
    this.size = 44,
    this.borderRadius = AppTheme.radiusSmall,
  });

  final String playlistId;
  final String playlistName;
  final List<String> albumIds;
  final WebApiClient? artworkClient;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final client = artworkClient;
    final radius = BorderRadius.circular(borderRadius);

    if (albumIds.isEmpty || client == null) {
      return _fallback(radius);
    }
    if (albumIds.length < 4) {
      return WebArtwork(
        client: client,
        albumId: albumIds.first,
        size: size,
        borderRadius: borderRadius,
        placeholderIcon: Icons.queue_music_rounded,
        deferDuringScroll: true,
      );
    }

    final half = size / 2;
    Widget cell(String albumId) => WebArtwork(
          client: client,
          albumId: albumId,
          size: half,
          borderRadius: 0,
          thumbnail: true,
          iconScale: 0.4,
          deferDuringScroll: true,
        );

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [cell(albumIds[0]), cell(albumIds[1])]),
            Row(children: [cell(albumIds[2]), cell(albumIds[3])]),
          ],
        ),
      ),
    );
  }

  Widget _fallback(BorderRadius radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4527A0), Color(0xFF7E57C2)],
        ),
      ),
      child: Icon(
        Icons.queue_music_rounded,
        color: Colors.white.withValues(alpha: 0.9),
        size: size * 0.46,
      ),
    );
  }
}

/// Square song/album cover thumbnail for individual tracks.
class CurationSongArtwork extends StatelessWidget {
  const CurationSongArtwork({
    super.key,
    required this.song,
    this.artworkClient,
    this.size = 44,
  });

  final CurationCatalogSong song;
  final WebApiClient? artworkClient;
  final double size;

  @override
  Widget build(BuildContext context) {
    return WebArtwork(
      client: artworkClient,
      albumId: song.albumId,
      songId: song.id,
      size: size,
      borderRadius: AppTheme.radiusSmall,
      deferDuringScroll: true,
    );
  }
}

/// Compact 64 px artist row with artwork, selection summary, optional drill
/// chevron, and independent check circle.
class CurationArtistTile extends StatelessWidget {
  const CurationArtistTile({
    super.key,
    required this.group,
    required this.selectionState,
    required this.includedCount,
    required this.onTap,
    required this.onToggleWhole,
    this.artworkClient,
    this.fallbackAlbumId,
    this.fallbackSongId,
    this.isWideSelected = false,
    this.showChevron = true,
  });

  final CurationArtistGroup group;
  final CurationArtistSelectionState selectionState;
  final int includedCount;
  final VoidCallback onTap;
  final VoidCallback onToggleWhole;
  final WebApiClient? artworkClient;
  final String? fallbackAlbumId;
  final String? fallbackSongId;
  final bool isWideSelected;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
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
        fallbackSongId:
            fallbackSongId ?? group.standaloneSongs.firstOrNull?.id,
        artworkClient: artworkClient,
      ),
      title: group.displayName,
      subtitle: parts.join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showChevron)
            const Padding(
              padding: EdgeInsets.only(right: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppTheme.textSecondary,
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
    this.artworkClient,
    this.onOpenTracks,
  });

  final CurationCatalogAlbum album;
  final CurationArtistSelectionState selectionState;
  final int includedTrackCount;
  final int totalTrackCount;
  final VoidCallback onToggle;
  final WebApiClient? artworkClient;
  final VoidCallback? onOpenTracks;

  @override
  Widget build(BuildContext context) {
    final trackLabel = totalTrackCount > 0 &&
            selectionState == CurationArtistSelectionState.partial
        ? '$includedTrackCount/$totalTrackCount tracks'
        : '${album.songCount} ${album.songCount == 1 ? 'song' : 'songs'}';

    return _CurationRowShell(
      onTap: onToggle,
      leading: CurationAlbumArtwork(
        albumId: album.id,
        artworkClient: artworkClient,
      ),
      title: album.title,
      subtitle: '${album.artist} · $trackLabel',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onOpenTracks != null)
            IconButton(
              icon: const Icon(
                Icons.format_list_bulleted_rounded,
                size: 18,
                color: AppTheme.textSecondary,
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
    this.artworkClient,
  });

  final CurationCatalogPlaylist playlist;
  final List<String> albumIds;
  final bool included;
  final VoidCallback onToggle;
  final WebApiClient? artworkClient;

  @override
  Widget build(BuildContext context) {
    return _CurationRowShell(
      onTap: onToggle,
      leading: CurationPlaylistArtwork(
        playlistId: playlist.id,
        playlistName: playlist.name,
        albumIds: albumIds,
        artworkClient: artworkClient,
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
    this.artworkClient,
  });

  final CurationCatalogSong song;
  final String? albumTitle;
  final bool included;
  final VoidCallback onToggle;
  final WebApiClient? artworkClient;

  @override
  Widget build(BuildContext context) {
    final subtitle = albumTitle != null && albumTitle!.isNotEmpty
        ? '${song.artist} · $albumTitle'
        : song.artist;

    return _CurationRowShell(
      onTap: onToggle,
      leading: CurationSongArtwork(
        song: song,
        artworkClient: artworkClient,
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
    return SizedBox(
      height: kCurationRowHeight,
      child: Material(
        color: highlighted ? AppTheme.surfaceHover : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.border.withValues(alpha: 0.6),
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontFeatures: _tabularFigures,
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
