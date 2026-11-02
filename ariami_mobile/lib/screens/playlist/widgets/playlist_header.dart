import 'dart:io';
import 'package:flutter/material.dart';
import '../../../models/api_models.dart';
import '../../../widgets/common/sleeve_header.dart';
import 'artwork_collage.dart';
import 'fallback_header.dart';
import '../../../utils/image_decode.dart';

class PlaylistHeader extends StatelessWidget {
  final PlaylistModel? playlist;

  final List<SongModel> songs;

  final String? baseUrl;

  const PlaylistHeader({
    super.key,
    this.playlist,
    required this.songs,
    this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    Widget artworkWidget;

    if (playlist?.customImagePath != null &&
        File(playlist!.customImagePath!).existsSync()) {
      artworkWidget = Image(
        image: resizedForDisplay(
          context,
          FileImage(File(playlist!.customImagePath!)),
          280,
        ),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          return _buildArtworkFromSongs();
        },
      );
    } else {
      artworkWidget = _buildArtworkFromSongs();
    }

    return SleeveHeader(cover: artworkWidget);
  }

  Widget _buildArtworkFromSongs() {
    // Get unique artwork IDs from songs for artwork collage
    // - Album songs: use albumId
    // - Standalone songs: use "song_{songId}" prefix
    final artworkIds = <String>[];
    for (final song in songs) {
      if (song.albumId != null) {
        if (!artworkIds.contains(song.albumId)) {
          artworkIds.add(song.albumId!);
        }
      } else {
        final songArtworkId = 'song_${song.id}';
        if (!artworkIds.contains(songArtworkId)) {
          artworkIds.add(songArtworkId);
        }
      }
      if (artworkIds.length >= 4) break;
    }

    if (artworkIds.isNotEmpty) {
      return ArtworkCollage(
        artworkIds: artworkIds,
        baseUrl: baseUrl,
      );
    }

    return FallbackHeader(playlistName: playlist?.name);
  }
}
