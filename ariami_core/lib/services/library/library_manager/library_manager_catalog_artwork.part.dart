part of '../library_manager.dart';

extension _LibraryManagerCatalogArtworkPart on LibraryManager {
  Future<void> _precomputeAndPersistArtworkVariantsForAlbums({
    required LibraryStructure library,
    required Iterable<String> albumIds,
  }) async {
    if (!_shouldPrecomputeArtwork) {
      return;
    }

    final catalogWriter = _catalogWriter;
    final artworkService = _artworkPrecomputeService;
    if (catalogWriter == null || artworkService == null) {
      return;
    }

    final orderedAlbumIds = albumIds.toSet().toList()..sort();
    for (final albumId in orderedAlbumIds) {
      final album = library.albums[albumId];
      if (album == null || !album.isValid) {
        continue;
      }

      try {
        final source = await _extractAlbumArtworkSource(album);
        if (source == null) {
          continue;
        }

        final fullEtag = _computeArtworkEtag(source.artworkBytes);
        final fullMimeType = _detectArtworkMimeType(source.artworkBytes);
        catalogWriter.upsertArtworkVariant(
          CatalogArtworkVariantRecord(
            artworkKey: album.id,
            variant: 'full',
            mimeType: fullMimeType,
            byteSize: source.artworkBytes.length,
            etag: fullEtag,
            lastModifiedEpochMs: source.lastModifiedEpochMs,
            storagePath: source.referencePath,
            updatedToken: _latestCatalogToken,
          ),
        );

        final thumbnailBytes = await artworkService.precomputeArtworkVariant(
          album.id,
          source.artworkBytes,
          ArtworkSize.thumbnail,
        );
        final expectedThumbnailPath = artworkService.getVariantStoragePath(
          album.id,
          ArtworkSize.thumbnail,
          originalReferencePath: source.referencePath,
        );
        final thumbnailFile = File(expectedThumbnailPath);
        final thumbnailExists = await thumbnailFile.exists();
        final thumbnailStoragePath =
            thumbnailExists ? thumbnailFile.path : source.referencePath;
        final thumbnailLastModified = thumbnailExists
            ? (await thumbnailFile.stat()).modified.millisecondsSinceEpoch
            : source.lastModifiedEpochMs;
        catalogWriter.upsertArtworkVariant(
          CatalogArtworkVariantRecord(
            artworkKey: album.id,
            variant: 'thumb_200',
            mimeType: _detectArtworkMimeType(thumbnailBytes),
            byteSize: thumbnailBytes.length,
            etag: _computeArtworkEtag(thumbnailBytes),
            lastModifiedEpochMs: thumbnailLastModified,
            storagePath: thumbnailStoragePath,
            updatedToken: _latestCatalogToken,
          ),
        );
        _markAlbumHasArtworkInMemory(album.id);
      } catch (e) {
        print('[LibraryManager] WARNING: Failed artwork precompute for '
            'album $albumId: $e');
      }
    }
  }

  Future<_AlbumArtworkSource?> _extractAlbumArtworkSource(Album album) async {
    if (_artworkCache.containsKey(album.id)) {
      final cachedArtwork = _artworkCache[album.id];
      if (cachedArtwork == null) {
        return null;
      }

      final referencePath = album.artworkPath ??
          (album.songs.isNotEmpty ? album.songs.first.filePath : null);
      if (referencePath == null) {
        return null;
      }

      return _AlbumArtworkSource(
        artworkBytes: cachedArtwork,
        referencePath: referencePath,
        lastModifiedEpochMs: _artworkReferenceModifiedEpochMs(
          album,
          referencePath,
        ),
      );
    }

    final sidecarOrLazyPath = album.artworkPath;
    if (sidecarOrLazyPath != null && _isImageFilePath(sidecarOrLazyPath)) {
      try {
        final sidecarFile = File(sidecarOrLazyPath);
        if (await sidecarFile.exists()) {
          final artworkBytes = await sidecarFile.readAsBytes();
          if (artworkBytes.isNotEmpty) {
            _artworkCache[album.id] = artworkBytes;
            return _AlbumArtworkSource(
              artworkBytes: artworkBytes,
              referencePath: sidecarOrLazyPath,
              lastModifiedEpochMs:
                  (await sidecarFile.stat()).modified.millisecondsSinceEpoch,
            );
          }
        }
      } catch (_) {
        // Fall through to embedded extraction.
      }
    }

    for (final song in album.songs) {
      final artwork = await _metadataExtractor.extractArtwork(song.filePath);
      if (artwork != null) {
        _artworkCache[album.id] = artwork;
        return _AlbumArtworkSource(
          artworkBytes: artwork,
          referencePath: song.filePath,
          lastModifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    _artworkCache[album.id] = null;
    return null;
  }

  String _computeArtworkEtag(List<int> artworkBytes) {
    return md5.convert(artworkBytes).toString();
  }

  String _detectArtworkMimeType(List<int> artworkBytes) {
    if (artworkBytes.length >= 3 &&
        artworkBytes[0] == 0xFF &&
        artworkBytes[1] == 0xD8 &&
        artworkBytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    if (artworkBytes.length >= 8 &&
        artworkBytes[0] == 0x89 &&
        artworkBytes[1] == 0x50 &&
        artworkBytes[2] == 0x4E &&
        artworkBytes[3] == 0x47 &&
        artworkBytes[4] == 0x0D &&
        artworkBytes[5] == 0x0A &&
        artworkBytes[6] == 0x1A &&
        artworkBytes[7] == 0x0A) {
      return 'image/png';
    }

    if (artworkBytes.length >= 6 &&
        artworkBytes[0] == 0x47 &&
        artworkBytes[1] == 0x49 &&
        artworkBytes[2] == 0x46 &&
        artworkBytes[3] == 0x38 &&
        (artworkBytes[4] == 0x37 || artworkBytes[4] == 0x39) &&
        artworkBytes[5] == 0x61) {
      return 'image/gif';
    }

    if (artworkBytes.length >= 12 &&
        artworkBytes[0] == 0x52 &&
        artworkBytes[1] == 0x49 &&
        artworkBytes[2] == 0x46 &&
        artworkBytes[3] == 0x46 &&
        artworkBytes[8] == 0x57 &&
        artworkBytes[9] == 0x45 &&
        artworkBytes[10] == 0x42 &&
        artworkBytes[11] == 0x50) {
      return 'image/webp';
    }

    return 'image/jpeg';
  }

  void _markAlbumHasArtworkInMemory(String albumId) {
    final library = _library;
    if (library == null) {
      return;
    }

    final album = library.albums[albumId];
    if (album == null || album.hasArtwork) {
      return;
    }

    final updatedAlbums = Map<String, Album>.from(library.albums);
    updatedAlbums[albumId] = album.copyWith(hasArtwork: true);
    _library = LibraryStructure(
      albums: updatedAlbums,
      standaloneSongs: library.standaloneSongs,
      folderPlaylists: library.folderPlaylists,
    );
  }

  bool _isImageFilePath(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return extension == '.jpg' ||
        extension == '.jpeg' ||
        extension == '.png' ||
        extension == '.gif' ||
        extension == '.webp';
  }

  int _artworkReferenceModifiedEpochMs(Album album, String referencePath) {
    for (final song in album.songs) {
      if (song.filePath == referencePath) {
        return song.modifiedTime?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch;
      }
    }

    try {
      return File(referencePath).statSync().modified.millisecondsSinceEpoch;
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch;
    }
  }
}

class _AlbumArtworkSource {
  _AlbumArtworkSource({
    required this.artworkBytes,
    required this.referencePath,
    required this.lastModifiedEpochMs,
  });

  final List<int> artworkBytes;
  final String referencePath;
  final int lastModifiedEpochMs;
}
