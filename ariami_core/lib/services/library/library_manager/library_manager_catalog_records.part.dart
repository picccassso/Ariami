part of '../library_manager.dart';

extension _LibraryManagerCatalogRecordsPart on LibraryManager {
  Map<String, CatalogSongRecord> _buildCatalogSongRecordsById(
    LibraryStructure library,
  ) {
    final records = <String, CatalogSongRecord>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final songId = _generateSongId(song.filePath);
        records[songId] = CatalogSongRecord(
          id: songId,
          filePath: song.filePath,
          title: song.title ?? _getFilenameWithoutExtension(song.filePath),
          artist: song.artist ?? 'Unknown Artist',
          albumId: album.id,
          durationSeconds: song.duration ?? 0,
          trackNumber: song.trackNumber,
          fileSizeBytes: song.fileSize,
          modifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch,
          bitrateKbps: song.bitrate,
          artworkKey: album.id,
          updatedToken: 0,
          isDeleted: false,
        );
      }
    }

    for (final song in library.standaloneSongs) {
      final songId = _generateSongId(song.filePath);
      records[songId] = CatalogSongRecord(
        id: songId,
        filePath: song.filePath,
        title: song.title ?? _getFilenameWithoutExtension(song.filePath),
        artist: song.artist ?? 'Unknown Artist',
        albumId: null,
        durationSeconds: song.duration ?? 0,
        trackNumber: song.trackNumber,
        fileSizeBytes: song.fileSize,
        modifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch,
        bitrateKbps: song.bitrate,
        artworkKey: null,
        updatedToken: 0,
        isDeleted: false,
      );
    }

    return records;
  }

  Map<String, CatalogAlbumRecord> _buildCatalogAlbumRecordsById(
    LibraryStructure library,
  ) {
    final records = <String, CatalogAlbumRecord>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      var durationSeconds = 0;
      for (final song in album.songs) {
        final duration = song.duration;
        if (duration != null && duration > 0) {
          durationSeconds += duration;
        }
      }

      records[album.id] = CatalogAlbumRecord(
        id: album.id,
        title: album.title,
        artist: album.artist,
        year: album.year,
        coverArtKey: album.hasArtwork ? album.id : null,
        songCount: album.songCount,
        durationSeconds: durationSeconds,
        updatedToken: 0,
        isDeleted: false,
      );
    }

    return records;
  }

  Map<String, CatalogPlaylistRecord> _buildCatalogPlaylistRecordsById(
    LibraryStructure library,
  ) {
    final records = <String, CatalogPlaylistRecord>{};
    final songDurationsById = _buildSongDurationsById(library);

    for (final playlist in library.folderPlaylists) {
      records[playlist.id] = CatalogPlaylistRecord(
        id: playlist.id,
        name: playlist.name,
        songCount: playlist.songCount,
        durationSeconds:
            _playlistDurationSeconds(playlist.songIds, songDurationsById),
        updatedToken: 0,
        isDeleted: false,
      );
    }

    return records;
  }

  Map<_CatalogPlaylistSongKey, int> _buildCatalogPlaylistSongPositions(
    LibraryStructure library,
  ) {
    final positions = <_CatalogPlaylistSongKey, int>{};

    for (final playlist in library.folderPlaylists) {
      for (var index = 0; index < playlist.songIds.length; index++) {
        positions[_CatalogPlaylistSongKey(
          playlistId: playlist.id,
          songId: playlist.songIds[index],
          position: index,
        )] = index;
      }
    }

    return positions;
  }

  Map<String, String?> _buildSongAlbumIdIndex(LibraryStructure library) {
    final index = <String, String?>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final songId = _generateSongId(song.filePath);
        index[songId] = album.id;
      }
    }

    for (final song in library.standaloneSongs) {
      final songId = _generateSongId(song.filePath);
      index[songId] = null;
    }

    return index;
  }

  Map<String, int> _buildSongDurationsById(LibraryStructure library) {
    final durationsById = <String, int>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final duration = song.duration;
        if (duration != null && duration > 0) {
          durationsById[_generateSongId(song.filePath)] = duration;
        }
      }
    }

    for (final song in library.standaloneSongs) {
      final duration = song.duration;
      if (duration != null && duration > 0) {
        durationsById[_generateSongId(song.filePath)] = duration;
      }
    }

    return durationsById;
  }

  int _playlistDurationSeconds(
    List<String> songIds,
    Map<String, int> songDurationsById,
  ) {
    var totalDurationSeconds = 0;
    for (final songId in songIds) {
      totalDurationSeconds += songDurationsById[songId] ?? 0;
    }
    return totalDurationSeconds;
  }

  bool _playlistRecordChanged(
    CatalogPlaylistRecord? previous,
    CatalogPlaylistRecord current,
  ) {
    if (previous == null) {
      return true;
    }

    return previous.name != current.name ||
        previous.songCount != current.songCount ||
        previous.durationSeconds != current.durationSeconds;
  }
}

class _CatalogPlaylistSongKey implements Comparable<_CatalogPlaylistSongKey> {
  const _CatalogPlaylistSongKey({
    required this.playlistId,
    required this.songId,
    required this.position,
  });

  final String playlistId;
  final String songId;
  final int position;

  String get entityId => '$playlistId:$position';

  @override
  int compareTo(_CatalogPlaylistSongKey other) {
    final playlistCompare = playlistId.compareTo(other.playlistId);
    if (playlistCompare != 0) {
      return playlistCompare;
    }
    final positionCompare = position.compareTo(other.position);
    if (positionCompare != 0) {
      return positionCompare;
    }
    return songId.compareTo(other.songId);
  }

  @override
  bool operator ==(Object other) {
    return other is _CatalogPlaylistSongKey &&
        other.playlistId == playlistId &&
        other.songId == songId &&
        other.position == position;
  }

  @override
  int get hashCode => Object.hash(playlistId, songId, position);
}
