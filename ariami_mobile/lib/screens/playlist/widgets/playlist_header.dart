import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../models/api_models.dart';
import 'artwork_collage.dart';
import 'fallback_header.dart';

/// Playlist header that displays custom image, artwork collage, or fallback
class PlaylistHeader extends StatelessWidget {
  /// The playlist model containing metadata
  final PlaylistModel? playlist;

  /// List of songs to extract artwork IDs from
  final List<SongModel> songs;

  /// Base URL for artwork images (from connection service)
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
    
    // Priority 1: Custom user-selected image
    if (playlist?.customImagePath != null && File(playlist!.customImagePath!).existsSync()) {
      artworkWidget = Image.file(
        File(playlist!.customImagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          return _buildArtworkFromSongs();
        },
      );
    } else {
      // Priority 2: Album artwork collage or fallback
      artworkWidget = _buildArtworkFromSongs();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred background artwork
        Positioned.fill(
          child: artworkWidget,
        ),
        
        // Blur effect and gradient overlay
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Centered clear artwork with shadow
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 40.0, bottom: 20.0),
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                child: artworkWidget,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build artwork from songs (collage or fallback)
  Widget _buildArtworkFromSongs() {
    // Get unique artwork IDs from songs for artwork collage
    // - Album songs: use albumId
    // - Standalone songs: use "song_{songId}" prefix
    final artworkIds = <String>[];
    for (final song in songs) {
      if (song.albumId != null) {
        // Song belongs to an album
        if (!artworkIds.contains(song.albumId)) {
          artworkIds.add(song.albumId!);
        }
      } else {
        // Standalone song - use song ID with prefix
        final songArtworkId = 'song_${song.id}';
        if (!artworkIds.contains(songArtworkId)) {
          artworkIds.add(songArtworkId);
        }
      }
      if (artworkIds.length >= 4) break;
    }

    // If we have artwork IDs, show collage (CachedArtwork handles offline)
    if (artworkIds.isNotEmpty) {
      return ArtworkCollage(
        artworkIds: artworkIds,
        baseUrl: baseUrl,
      );
    }

    // Fallback to gradient with icon
    return FallbackHeader(playlistName: playlist?.name);
  }
}
