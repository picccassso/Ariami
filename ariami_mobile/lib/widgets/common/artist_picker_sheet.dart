import 'dart:math';

import 'package:ariami_core/services/stats/credited_artist_splitter.dart';
import 'package:flutter/material.dart';

import '../../screens/main/library/library_controller.dart';
import '../../services/api/connection_service.dart';
import '../../services/artist_image_service.dart';
import 'cached_artwork.dart';
import 'mini_player_aware_bottom_sheet.dart';

/// Opens the artist's page, or prompts with a bottom sheet picker if the
/// artist string contains multiple credited collaborating artists.
///
/// Returns the chosen artist's display name, or null if the picker was dismissed.
Future<String?> openArtistOrPicker(
  BuildContext context, {
  required String artistName,
  String? songTitle,
  String? fallbackArtworkUrl,
  String? fallbackAlbumId,
}) async {
  final splitter = CreditedArtistSplitter();
  final credits = splitter.split(artistName);

  if (credits.length <= 1) {
    return credits.isEmpty ? artistName : credits.first.display;
  }

  return showArtistPickerSheet(
    context: context,
    artistName: artistName,
    credits: credits,
    songTitle: songTitle,
    fallbackArtworkUrl: fallbackArtworkUrl,
    fallbackAlbumId: fallbackAlbumId,
  );
}

/// Displays an "Artists" bottom sheet allowing the user to select which
/// collaborator to view.
Future<String?> showArtistPickerSheet({
  required BuildContext context,
  required String artistName,
  List<CreditedArtist>? credits,
  String? songTitle,
  String? fallbackArtworkUrl,
  String? fallbackAlbumId,
}) {
  final resolvedCredits = credits ?? CreditedArtistSplitter().split(artistName);

  return showAriamiSheet<String>(
    context: context,
    header: AriamiSheetHeader(
      title: 'Artists',
      subtitle: songTitle,
    ),
    items: [
      for (final credit in resolvedCredits)
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: SizedBox(
            width: 44,
            height: 44,
            child: _ArtistAvatar(
              artistName: credit.display,
              fallbackArtworkUrl: fallbackArtworkUrl,
              fallbackAlbumId: fallbackAlbumId,
            ),
          ),
          title: Text(
            credit.display,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          onTap: () => Navigator.of(context).pop(credit.display),
        ),
    ],
  );
}

class _ArtworkSource {
  final String cacheId;
  final String? url;

  const _ArtworkSource({required this.cacheId, this.url});
}

class _ArtistAvatar extends StatefulWidget {
  const _ArtistAvatar({
    required this.artistName,
    this.fallbackArtworkUrl,
    this.fallbackAlbumId,
  });

  final String artistName;
  final String? fallbackArtworkUrl;
  final String? fallbackAlbumId;

  @override
  State<_ArtistAvatar> createState() => _ArtistAvatarState();
}

class _ArtistAvatarState extends State<_ArtistAvatar> {
  _ArtworkSource? _resolvedSource;

  @override
  void initState() {
    super.initState();
    _resolveArtwork();
  }

  @override
  void didUpdateWidget(covariant _ArtistAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artistName != widget.artistName ||
        oldWidget.fallbackArtworkUrl != widget.fallbackArtworkUrl ||
        oldWidget.fallbackAlbumId != widget.fallbackAlbumId) {
      _resolveArtwork();
    }
  }

  void _resolveArtwork() {
    final customVersion =
        ArtistImageService().artistImageVersion(widget.artistName);
    final apiClient = ConnectionService().apiClient;

    if (customVersion != null && apiClient != null) {
      _resolvedSource = _ArtworkSource(
        cacheId:
            'artist_${normalizeArtistKey(widget.artistName)}_v$customVersion',
        url: apiClient.artistImageUrl(widget.artistName, version: customVersion),
      );
      return;
    }

    final library = LibraryController();
    final candidates = <_ArtworkSource>[];

    // Check albums the artist owns or appears on
    final albums = [
      ...library.artistAlbums(widget.artistName),
      ...library.artistAppearsOn(widget.artistName),
    ];
    for (final album in albums) {
      if (album.coverArt != null && album.coverArt!.isNotEmpty) {
        candidates.add(_ArtworkSource(
          cacheId: album.id,
          url: album.coverArt,
        ));
      }
    }

    // Check all tracks credited to the artist
    final tracks = library.artistTracks(widget.artistName);
    final albumsById = {for (final a in library.state.albums) a.id: a};
    for (final track in tracks) {
      final albumId = track.albumId;
      final album = albumId != null ? albumsById[albumId] : null;
      if (album?.coverArt != null && album!.coverArt!.isNotEmpty) {
        candidates.add(_ArtworkSource(
          cacheId: album.id,
          url: album.coverArt,
        ));
      } else if (apiClient != null) {
        candidates.add(_ArtworkSource(
          cacheId: 'song_${track.id}',
          url: '${apiClient.baseUrl}/song-artwork/${track.id}',
        ));
      }
    }

    // Deduplicate candidates by cacheId
    final uniqueCandidates = <String, _ArtworkSource>{};
    for (final c in candidates) {
      uniqueCandidates.putIfAbsent(c.cacheId, () => c);
    }

    if (uniqueCandidates.isNotEmpty) {
      final list = uniqueCandidates.values.toList();
      _resolvedSource = list[Random().nextInt(list.length)];
      return;
    }

    if (widget.fallbackArtworkUrl != null || widget.fallbackAlbumId != null) {
      _resolvedSource = _ArtworkSource(
        cacheId: widget.fallbackAlbumId ??
            'artist_${normalizeArtistKey(widget.artistName)}',
        url: widget.fallbackArtworkUrl,
      );
      return;
    }

    _resolvedSource = _ArtworkSource(
      cacheId: 'artist_${normalizeArtistKey(widget.artistName)}',
      url: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _resolvedSource ??
        _ArtworkSource(
          cacheId: 'artist_${normalizeArtistKey(widget.artistName)}',
          url: null,
        );

    return ClipOval(
      child: CachedArtwork(
        key: ValueKey('artist-picker-${source.cacheId}'),
        albumId: source.cacheId,
        artworkUrl: source.url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        fallbackIcon: Icons.person_rounded,
        fallbackIconSize: 22,
        sizeHint: ArtworkSizeHint.thumbnail,
      ),
    );
  }
}
