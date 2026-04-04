import 'dart:convert';

import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

class CatalogWriteResult {
  CatalogWriteResult({
    required this.upsertedAlbumCount,
    required this.upsertedSongCount,
    required this.upsertedPlaylistCount,
    required this.upsertedPlaylistSongCount,
    required this.deletedAlbumCount,
    required this.deletedSongCount,
    required this.deletedPlaylistCount,
    required this.deletedPlaylistSongCount,
    required this.latestToken,
  });

  final int upsertedAlbumCount;
  final int upsertedSongCount;
  final int upsertedPlaylistCount;
  final int upsertedPlaylistSongCount;
  final int deletedAlbumCount;
  final int deletedSongCount;
  final int deletedPlaylistCount;
  final int deletedPlaylistSongCount;
  final int latestToken;
}

class CatalogArtworkVariantRecord {
  CatalogArtworkVariantRecord({
    required this.artworkKey,
    required this.variant,
    required this.mimeType,
    required this.byteSize,
    required this.etag,
    required this.lastModifiedEpochMs,
    required this.storagePath,
    required this.updatedToken,
  });

  final String artworkKey;
  final String variant;
  final String mimeType;
  final int byteSize;
  final String etag;
  final int lastModifiedEpochMs;
  final String storagePath;
  final int updatedToken;
}

/// Writes scanner output into catalog rows and library change events.
class CatalogWriter {
  CatalogWriter({required Database database})
      : _database = database,
        _repository = CatalogRepository(database: database) {
    _latestToken = _repository.getLatestToken();
  }

  final Database _database;
  final CatalogRepository _repository;
  late int _latestToken;

  int get latestToken => _latestToken;

  void upsertArtworkVariant(CatalogArtworkVariantRecord record) {
    _database.execute(
      '''
INSERT INTO artwork_variants (
  artwork_key,
  variant,
  mime_type,
  byte_size,
  etag,
  last_modified_epoch_ms,
  storage_path,
  updated_token
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(artwork_key, variant) DO UPDATE SET
  mime_type = excluded.mime_type,
  byte_size = excluded.byte_size,
  etag = excluded.etag,
  last_modified_epoch_ms = excluded.last_modified_epoch_ms,
  storage_path = excluded.storage_path,
  updated_token = excluded.updated_token;
''',
      <Object?>[
        record.artworkKey,
        record.variant,
        record.mimeType,
        record.byteSize,
        record.etag,
        record.lastModifiedEpochMs,
        record.storagePath,
        record.updatedToken,
      ],
    );
  }

  CatalogWriteResult writeFullSnapshot({
    required LibraryStructure library,
    required String Function(String filePath) songIdForPath,
  }) {
    final albumsById = _buildAlbumSnapshots(library);
    final songsById = _buildSongSnapshots(library, songIdForPath);
    final playlistsById = _buildPlaylistSnapshots(library, songIdForPath);
    final playlistSongsByKey =
        _buildPlaylistSongSnapshots(library, playlistsById);

    final existingAlbumIds = _selectActiveIds('albums');
    final existingSongIds = _selectActiveIds('songs');
    final existingPlaylistIds = _selectActiveIds('playlists');
    final existingPlaylistSongKeys = _selectPlaylistSongKeys();

    final deletedAlbumIds = existingAlbumIds
        .where((id) => !albumsById.containsKey(id))
        .toList()
      ..sort();
    final deletedSongIds = existingSongIds
        .where((id) => !songsById.containsKey(id))
        .toList()
      ..sort();
    final deletedPlaylistIds = existingPlaylistIds
        .where((id) => !playlistsById.containsKey(id))
        .toList()
      ..sort();
    final deletedPlaylistIdSet = deletedPlaylistIds.toSet();
    final deletedPlaylistSongKeys = existingPlaylistSongKeys
        .where(
          (key) =>
              !playlistSongsByKey.containsKey(key) &&
              !deletedPlaylistIdSet.contains(key.playlistId),
        )
        .toList()
      ..sort();

    final orderedAlbumIds = albumsById.keys.toList()..sort();
    final orderedSongIds = songsById.keys.toList()..sort();
    final orderedPlaylistIds = playlistsById.keys.toList()..sort();
    final orderedPlaylistSongKeys = playlistSongsByKey.keys.toList()..sort();

    final occurredEpochMs = DateTime.now().millisecondsSinceEpoch;
    var tokenCursor = _readLatestToken();

    _database.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      for (final albumId in orderedAlbumIds) {
        tokenCursor += 1;
        final snapshot = albumsById[albumId]!;
        _repository.upsertAlbum(
          CatalogAlbumRecord(
            id: snapshot.id,
            title: snapshot.title,
            artist: snapshot.artist,
            year: snapshot.year,
            coverArtKey: snapshot.coverArtKey,
            songCount: snapshot.songCount,
            durationSeconds: snapshot.durationSeconds,
            updatedToken: tokenCursor,
          ),
        );
        _insertChangeEvent(
          entityType: 'album',
          entityId: snapshot.id,
          op: 'upsert',
          payloadJson: _albumPayloadJson(snapshot),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final songId in orderedSongIds) {
        tokenCursor += 1;
        final snapshot = songsById[songId]!;
        _repository.upsertSong(
          CatalogSongRecord(
            id: snapshot.id,
            filePath: snapshot.filePath,
            title: snapshot.title,
            artist: snapshot.artist,
            albumId: snapshot.albumId,
            durationSeconds: snapshot.durationSeconds,
            trackNumber: snapshot.trackNumber,
            fileSizeBytes: snapshot.fileSizeBytes,
            modifiedEpochMs: snapshot.modifiedEpochMs,
            artworkKey: snapshot.artworkKey,
            updatedToken: tokenCursor,
          ),
        );
        _insertChangeEvent(
          entityType: 'song',
          entityId: snapshot.id,
          op: 'upsert',
          payloadJson: _songPayloadJson(snapshot),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final playlistId in orderedPlaylistIds) {
        tokenCursor += 1;
        final snapshot = playlistsById[playlistId]!;
        _repository.upsertPlaylist(
          CatalogPlaylistRecord(
            id: snapshot.id,
            name: snapshot.name,
            songCount: snapshot.songCount,
            durationSeconds: snapshot.durationSeconds,
            updatedToken: tokenCursor,
          ),
        );
        _insertChangeEvent(
          entityType: 'playlist',
          entityId: snapshot.id,
          op: 'upsert',
          payloadJson: _playlistPayloadJson(snapshot),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final key in orderedPlaylistSongKeys) {
        tokenCursor += 1;
        final snapshot = playlistSongsByKey[key]!;
        _repository.upsertPlaylistSong(
          CatalogPlaylistSongRecord(
            playlistId: snapshot.playlistId,
            songId: snapshot.songId,
            position: snapshot.position,
            updatedToken: tokenCursor,
          ),
        );
        _insertChangeEvent(
          entityType: 'playlist_song',
          entityId: snapshot.entityId,
          op: 'upsert',
          payloadJson: _playlistSongPayloadJson(snapshot),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final key in deletedPlaylistSongKeys) {
        tokenCursor += 1;
        _repository.deletePlaylistSong(key.playlistId, key.position);
        _insertChangeEvent(
          entityType: 'playlist_song',
          entityId: key.entityId,
          op: 'delete',
          payloadJson: _playlistSongDeletePayloadJson(key),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final songId in deletedSongIds) {
        tokenCursor += 1;
        _repository.softDeleteSong(songId, tokenCursor);
        _insertChangeEvent(
          entityType: 'song',
          entityId: songId,
          op: 'delete',
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final albumId in deletedAlbumIds) {
        tokenCursor += 1;
        _repository.softDeleteAlbum(albumId, tokenCursor);
        _insertChangeEvent(
          entityType: 'album',
          entityId: albumId,
          op: 'delete',
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final playlistId in deletedPlaylistIds) {
        tokenCursor += 1;
        _repository.softDeletePlaylist(playlistId, tokenCursor);
        _insertChangeEvent(
          entityType: 'playlist',
          entityId: playlistId,
          op: 'delete',
          occurredEpochMs: occurredEpochMs,
        );
      }

      _database.execute('COMMIT;');
    } catch (_) {
      _database.execute('ROLLBACK;');
      rethrow;
    }

    _latestToken = tokenCursor;
    return CatalogWriteResult(
      upsertedAlbumCount: orderedAlbumIds.length,
      upsertedSongCount: orderedSongIds.length,
      upsertedPlaylistCount: orderedPlaylistIds.length,
      upsertedPlaylistSongCount: orderedPlaylistSongKeys.length,
      deletedAlbumCount: deletedAlbumIds.length,
      deletedSongCount: deletedSongIds.length,
      deletedPlaylistCount: deletedPlaylistIds.length,
      deletedPlaylistSongCount: deletedPlaylistSongKeys.length,
      latestToken: tokenCursor,
    );
  }

  Map<String, _AlbumSnapshot> _buildAlbumSnapshots(LibraryStructure library) {
    final snapshots = <String, _AlbumSnapshot>{};
    for (final album in library.albums.values.where((a) => a.isValid)) {
      var durationSeconds = 0;
      for (final song in album.songs) {
        final duration = song.duration;
        if (duration != null && duration > 0) {
          durationSeconds += duration;
        }
      }

      snapshots[album.id] = _AlbumSnapshot(
        id: album.id,
        title: album.title,
        artist: album.artist,
        year: album.year,
        coverArtKey: album.artworkPath != null ? album.id : null,
        songCount: album.songCount,
        durationSeconds: durationSeconds,
      );
    }
    return snapshots;
  }

  Map<String, _SongSnapshot> _buildSongSnapshots(
    LibraryStructure library,
    String Function(String filePath) songIdForPath,
  ) {
    final snapshots = <String, _SongSnapshot>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final snapshot = _songToSnapshot(
          song: song,
          songIdForPath: songIdForPath,
          albumId: album.id,
        );
        snapshots[snapshot.id] = snapshot;
      }
    }

    for (final song in library.standaloneSongs) {
      final snapshot = _songToSnapshot(
        song: song,
        songIdForPath: songIdForPath,
        albumId: null,
      );
      snapshots[snapshot.id] = snapshot;
    }

    return snapshots;
  }

  Map<String, _PlaylistSnapshot> _buildPlaylistSnapshots(
    LibraryStructure library,
    String Function(String filePath) songIdForPath,
  ) {
    final snapshots = <String, _PlaylistSnapshot>{};
    final songDurationsById = _buildSongDurationsById(library, songIdForPath);
    for (final playlist in library.folderPlaylists) {
      snapshots[playlist.id] = _PlaylistSnapshot(
        id: playlist.id,
        name: playlist.name,
        songIds: List<String>.from(playlist.songIds),
        durationSeconds: _playlistDurationSeconds(
          playlist.songIds,
          songDurationsById,
        ),
      );
    }
    return snapshots;
  }

  Map<_PlaylistSongKey, _PlaylistSongSnapshot> _buildPlaylistSongSnapshots(
    LibraryStructure library,
    Map<String, _PlaylistSnapshot> playlistsById,
  ) {
    final snapshots = <_PlaylistSongKey, _PlaylistSongSnapshot>{};
    for (final playlist in library.folderPlaylists) {
      if (!playlistsById.containsKey(playlist.id)) {
        continue;
      }
      for (var index = 0; index < playlist.songIds.length; index++) {
        final songId = playlist.songIds[index];
        final key = _PlaylistSongKey(
          playlistId: playlist.id,
          songId: songId,
          position: index,
        );
        snapshots[key] = _PlaylistSongSnapshot(
          playlistId: playlist.id,
          songId: songId,
          position: index,
        );
      }
    }
    return snapshots;
  }

  _SongSnapshot _songToSnapshot({
    required SongMetadata song,
    required String Function(String filePath) songIdForPath,
    required String? albumId,
  }) {
    final title = (song.title != null && song.title!.trim().isNotEmpty)
        ? song.title!.trim()
        : path.basenameWithoutExtension(song.filePath);
    final artist = (song.artist != null && song.artist!.trim().isNotEmpty)
        ? song.artist!.trim()
        : 'Unknown Artist';

    return _SongSnapshot(
      id: songIdForPath(song.filePath),
      filePath: song.filePath,
      title: title,
      artist: artist,
      albumId: albumId,
      durationSeconds: song.duration ?? 0,
      trackNumber: song.trackNumber,
      fileSizeBytes: song.fileSize,
      modifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch,
      artworkKey: albumId,
    );
  }

  Map<String, int> _buildSongDurationsById(
    LibraryStructure library,
    String Function(String filePath) songIdForPath,
  ) {
    final durationsById = <String, int>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final duration = song.duration;
        if (duration != null && duration > 0) {
          durationsById[songIdForPath(song.filePath)] = duration;
        }
      }
    }

    for (final song in library.standaloneSongs) {
      final duration = song.duration;
      if (duration != null && duration > 0) {
        durationsById[songIdForPath(song.filePath)] = duration;
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

  List<String> _selectActiveIds(String tableName) {
    final rows = _database.select(
      '''
SELECT id
FROM $tableName
WHERE is_deleted = 0
ORDER BY id ASC;
''',
    );
    return rows.map((row) => row['id'] as String).toList();
  }

  List<_PlaylistSongKey> _selectPlaylistSongKeys() {
    final rows = _database.select(
      '''
SELECT playlist_id, song_id, position
FROM playlist_songs
ORDER BY playlist_id ASC, position ASC, song_id ASC;
''',
    );
    return rows
        .map(
          (row) => _PlaylistSongKey(
            playlistId: row['playlist_id'] as String,
            songId: row['song_id'] as String,
            position: row['position'] as int,
          ),
        )
        .toList();
  }

  int _readLatestToken() {
    final rows = _database.select(
      '''
SELECT COALESCE(MAX(token), 0) AS latest_token
FROM library_changes;
''',
    );
    return rows.first['latest_token'] as int;
  }

  void _insertChangeEvent({
    required String entityType,
    required String entityId,
    required String op,
    String? payloadJson,
    required int occurredEpochMs,
  }) {
    _database.execute(
      '''
INSERT INTO library_changes (
  entity_type,
  entity_id,
  op,
  payload_json,
  occurred_epoch_ms,
  actor_user_id
) VALUES (?, ?, ?, ?, ?, NULL);
''',
      <Object?>[
        entityType,
        entityId,
        op,
        payloadJson,
        occurredEpochMs,
      ],
    );
  }

  String _albumPayloadJson(_AlbumSnapshot snapshot) {
    return jsonEncode(<String, dynamic>{
      'id': snapshot.id,
      'title': snapshot.title,
      'artist': snapshot.artist,
      'coverArt': snapshot.coverArtKey == null
          ? null
          : '/api/artwork/${Uri.encodeComponent(snapshot.id)}',
      'songCount': snapshot.songCount,
      'duration': snapshot.durationSeconds,
    });
  }

  String _songPayloadJson(_SongSnapshot snapshot) {
    return jsonEncode(<String, dynamic>{
      'id': snapshot.id,
      'title': snapshot.title,
      'artist': snapshot.artist,
      'albumId': snapshot.albumId,
      'duration': snapshot.durationSeconds,
      'trackNumber': snapshot.trackNumber,
    });
  }

  String _playlistPayloadJson(_PlaylistSnapshot snapshot) {
    return jsonEncode(<String, dynamic>{
      'id': snapshot.id,
      'name': snapshot.name,
      'songCount': snapshot.songCount,
      'duration': snapshot.durationSeconds,
      'songIds': snapshot.songIds,
    });
  }

  String _playlistSongPayloadJson(_PlaylistSongSnapshot snapshot) {
    return jsonEncode(<String, dynamic>{
      'playlistId': snapshot.playlistId,
      'songId': snapshot.songId,
      'position': snapshot.position,
    });
  }

  String _playlistSongDeletePayloadJson(_PlaylistSongKey key) {
    return jsonEncode(<String, dynamic>{
      'playlistId': key.playlistId,
      'songId': key.songId,
      'position': key.position,
    });
  }
}

class _AlbumSnapshot {
  _AlbumSnapshot({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.coverArtKey,
    required this.songCount,
    required this.durationSeconds,
  });

  final String id;
  final String title;
  final String artist;
  final int? year;
  final String? coverArtKey;
  final int songCount;
  final int durationSeconds;
}

class _SongSnapshot {
  _SongSnapshot({
    required this.id,
    required this.filePath,
    required this.title,
    required this.artist,
    required this.albumId,
    required this.durationSeconds,
    required this.trackNumber,
    required this.fileSizeBytes,
    required this.modifiedEpochMs,
    required this.artworkKey,
  });

  final String id;
  final String filePath;
  final String title;
  final String artist;
  final String? albumId;
  final int durationSeconds;
  final int? trackNumber;
  final int? fileSizeBytes;
  final int? modifiedEpochMs;
  final String? artworkKey;
}

class _PlaylistSnapshot {
  _PlaylistSnapshot({
    required this.id,
    required this.name,
    required this.songIds,
    required this.durationSeconds,
  });

  final String id;
  final String name;
  final List<String> songIds;
  final int durationSeconds;

  int get songCount => songIds.length;
}

class _PlaylistSongSnapshot {
  _PlaylistSongSnapshot({
    required this.playlistId,
    required this.songId,
    required this.position,
  });

  final String playlistId;
  final String songId;
  final int position;

  String get entityId => '$playlistId:$position';
}

class _PlaylistSongKey implements Comparable<_PlaylistSongKey> {
  const _PlaylistSongKey({
    required this.playlistId,
    required this.songId,
    required this.position,
  });

  final String playlistId;
  final String songId;
  final int position;

  String get entityId => '$playlistId:$position';

  @override
  int compareTo(_PlaylistSongKey other) {
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
    return other is _PlaylistSongKey &&
        other.playlistId == playlistId &&
        other.songId == songId &&
        other.position == position;
  }

  @override
  int get hashCode => Object.hash(playlistId, songId, position);
}
