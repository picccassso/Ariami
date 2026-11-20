import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_api_client.dart';
import 'artwork.dart';

/// Playlist thumbnail. A custom cover photo synced from the account's image
/// store (picked on the phone) wins; otherwise it mirrors the mobile app:
/// the first up-to-four songs' artwork tiled into a 2×2 mosaic. With fewer
/// covers it falls back to a single image, and with none to a gradient tile.
class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({
    super.key,
    required this.playlist,
    this.size = 56,
    this.borderRadius = 8,
  });

  final PlaylistSummary playlist;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final client = context.read<ConnectionController>().client;
    final covers = library.playlistCoverTracks(playlist);
    final radius = BorderRadius.circular(borderRadius);

    final imageVersion = library.playlistImageVersion(playlist.id);
    if (imageVersion != null && client != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image(
          image: Artwork.cachedImage(
            client.playlistImageUrl(playlist.id, version: imageVersion),
            client,
            cacheWidth:
                (size * MediaQuery.devicePixelRatioOf(context) * 2).round(),
          ),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, _, __) => _songArtwork(client, covers),
        ),
      );
    }

    return _songArtwork(client, covers);
  }

  Widget _songArtwork(PlayerApiClient? client, List<Track> covers) {
    final radius = BorderRadius.circular(borderRadius);

    if (covers.isEmpty) {
      return _fallback(radius);
    }

    if (covers.length < 4) {
      final t = covers.first;
      return Artwork(
        client: client,
        albumId: t.albumId,
        songId: t.albumId == null ? t.id : null,
        size: size,
        borderRadius: borderRadius,
      );
    }

    final half = size / 2;
    Widget cell(Track t) => Artwork(
          client: client,
          albumId: t.albumId,
          songId: t.albumId == null ? t.id : null,
          size: half,
          borderRadius: 0,
          thumbnail: true,
          iconScale: 0.4,
        );

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [cell(covers[0]), cell(covers[1])]),
            Row(children: [cell(covers[2]), cell(covers[3])]),
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
        size: size * 0.42,
      ),
    );
  }
}
