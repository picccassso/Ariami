import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../services/cache/cache_manager.dart';

/// Cover art for a song: album artwork when the song belongs to an album,
/// otherwise the standalone song artwork endpoint.
///
/// Reads the artwork already cached in memory — the list row behind the menu
/// has usually loaded it — and falls back to a colored music-note tile while
/// the artwork is not cached yet.
class SongArtwork extends StatelessWidget {
  final SongModel song;
  final double size;
  final BorderRadius borderRadius;

  const SongArtwork({
    super.key,
    required this.song,
    this.size = 44,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: _content(),
      ),
    );
  }

  Widget _content() {
    final path = _cachedArtworkPath();
    if (path == null) return _fallbackTile();
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => _fallbackTile(),
    );
  }

  String? _cachedArtworkPath() {
    final albumId = song.albumId;
    final cacheId =
        albumId == null || albumId.isEmpty ? 'song_${song.id}' : albumId;
    final cacheManager = CacheManager();
    return cacheManager.getArtworkPathSync('${cacheId}_thumb') ??
        cacheManager.getArtworkPathSync(cacheId);
  }

  Widget _fallbackTile() {
    return Container(
      color: _fallbackColor(),
      child: Icon(
        Icons.music_note,
        size: size * 0.5,
        color: Colors.white,
      ),
    );
  }

  Color _fallbackColor() {
    const colors = [
      Colors.blue,
      Colors.purple,
      Colors.green,
      Colors.orange,
      Colors.pink,
    ];
    final id = song.albumId ?? song.id;
    return colors[id.hashCode.abs() % colors.length][300]!;
  }
}
