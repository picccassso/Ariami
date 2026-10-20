import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/catalog/catalog_change_log.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/catalog/song_attribute_repository.dart';
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
    var tokenCursor = readLatestChangeToken(_database);
    final snapshotStartToken = tokenCursor + 1;

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
        insertChangeEvent(
          _database,
          entityType: 'album',
          entityId: snapshot.id,
          op: 'upsert',
          payloadJson: albumChangePayloadJson(
            id: snapshot.id,
            title: snapshot.title,
            artist: snapshot.artist,
            coverArtKey: snapshot.coverArtKey,
            songCount: snapshot.songCount,
            durationSeconds: snapshot.durationSeconds,
          ),
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
            genre: snapshot.genre,
            albumId: snapshot.albumId,
            durationSeconds: snapshot.durationSeconds,
            trackNumber: snapshot.trackNumber,
            fileSizeBytes: snapshot.fileSizeBytes,
            modifiedEpochMs: snapshot.modifiedEpochMs,
            artworkKey: snapshot.artworkKey,
            updatedToken: tokenCursor,
            hasLyrics: snapshot.hasLyrics,
            isInstrumental: snapshot.isInstrumental,
          ),
        );
        insertChangeEvent(
          _database,
          entityType: 'song',
          entityId: snapshot.id,
          op: 'upsert',
          payloadJson: songChangePayloadJson(
            id: snapshot.id,
            title: snapshot.title,
            artist: snapshot.artist,
            genre: snapshot.genre,
            albumId: snapshot.albumId,
            durationSeconds: snapshot.durationSeconds,
            trackNumber: snapshot.trackNumber,
            hasLyrics: snapshot.hasLyrics,
            isInstrumental: snapshot.isInstrumental,
          ),
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
        insertChangeEvent(
          _database,
          entityType: 'playlist',
          entityId: snapshot.id,
          op: 'upsert',
          payloadJson: playlistChangePayloadJson(
            id: snapshot.id,
            name: snapshot.name,
            songCount: snapshot.songCount,
            durationSeconds: snapshot.durationSeconds,
            songIds: snapshot.songIds,
          ),
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
        insertChangeEvent(
          _database,
          entityType: 'playlist_song',
          entityId: snapshot.entityId,
          op: 'upsert',
          payloadJson: playlistSongChangePayloadJson(
            snapshot.playlistId,
            snapshot.songId,
            snapshot.position,
          ),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final key in deletedPlaylistSongKeys) {
        tokenCursor += 1;
        _repository.deletePlaylistSong(key.playlistId, key.position);
        insertChangeEvent(
          _database,
          entityType: 'playlist_song',
          entityId: key.entityId,
          op: 'delete',
          payloadJson: playlistSongChangePayloadJson(
            key.playlistId,
            key.songId,
            key.position,
          ),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final songId in deletedSongIds) {
        tokenCursor += 1;
        _repository.softDeleteSong(songId, tokenCursor);
        insertChangeEvent(
          _database,
          entityType: 'song',
          entityId: songId,
          op: 'delete',
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final albumId in deletedAlbumIds) {
        tokenCursor += 1;
        _repository.softDeleteAlbum(albumId, tokenCursor);
        insertChangeEvent(
          _database,
          entityType: 'album',
          entityId: albumId,
          op: 'delete',
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final playlistId in deletedPlaylistIds) {
        tokenCursor += 1;
        _repository.softDeletePlaylist(playlistId, tokenCursor);
        insertChangeEvent(
          _database,
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

    // Prune only history before this snapshot. Even very large snapshots must
    // remain complete so clients never receive a partial change set.
    _repository.pruneOldChangeEvents(
      100000,
      preserveFromToken: snapshotStartToken,
    );

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
        coverArtKey: album.hasArtwork ? album.id : null,
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
    final instrumentalOverrides = _repository.songAttributes
        .readKey(SongAttributeRepository.instrumentalKey);

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final snapshot = _songToSnapshot(
          song: song,
          songIdForPath: songIdForPath,
          albumId: album.id,
          instrumentalOverrides: instrumentalOverrides,
        );
        snapshots[snapshot.id] = snapshot;
      }
    }

    for (final song in library.standaloneSongs) {
      final snapshot = _songToSnapshot(
        song: song,
        songIdForPath: songIdForPath,
        albumId: null,
        instrumentalOverrides: instrumentalOverrides,
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

  Map<CatalogPlaylistSongKey, _PlaylistSongSnapshot>
      _buildPlaylistSongSnapshots(
    LibraryStructure library,
    Map<String, _PlaylistSnapshot> playlistsById,
  ) {
    final snapshots = <CatalogPlaylistSongKey, _PlaylistSongSnapshot>{};
    for (final playlist in library.folderPlaylists) {
      if (!playlistsById.containsKey(playlist.id)) {
        continue;
      }
      for (var index = 0; index < playlist.songIds.length; index++) {
        final songId = playlist.songIds[index];
        final key = CatalogPlaylistSongKey(
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
    required Map<String, Object> instrumentalOverrides,
  }) {
    final id = songIdForPath(song.filePath);
    final title = (song.title != null && song.title!.trim().isNotEmpty)
        ? song.title!.trim()
        : path.basenameWithoutExtension(song.filePath);
    final artist = (song.artist != null && song.artist!.trim().isNotEmpty)
        ? song.artist!.trim()
        : 'Unknown Artist';

    return _SongSnapshot(
      id: id,
      filePath: song.filePath,
      title: title,
      artist: artist,
      genre: song.genre,
      albumId: albumId,
      durationSeconds: song.duration ?? 0,
      trackNumber: song.trackNumber,
      fileSizeBytes: song.fileSize,
      modifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch,
      artworkKey: albumId,
      hasLyrics: song.hasLyrics,
      isInstrumental: song.resolveInstrumental(instrumentalOverrides[id]),
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

  List<CatalogPlaylistSongKey> _selectPlaylistSongKeys() {
    final rows = _database.select(
      '''
SELECT playlist_id, song_id, position
FROM playlist_songs
ORDER BY playlist_id ASC, position ASC, song_id ASC;
''',
    );
    return rows
        .map(
          (row) => CatalogPlaylistSongKey(
            playlistId: row['playlist_id'] as String,
            songId: row['song_id'] as String,
            position: row['position'] as int,
          ),
        )
        .toList();
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
    required this.genre,
    required this.albumId,
    required this.durationSeconds,
    required this.trackNumber,
    required this.fileSizeBytes,
    required this.modifiedEpochMs,
    required this.artworkKey,
    required this.hasLyrics,
    required this.isInstrumental,
  });

  final String id;
  final String filePath;
  final String title;
  final String artist;
  final String? genre;
  final String? albumId;
  final int durationSeconds;
  final int? trackNumber;
  final int? fileSizeBytes;
  final int? modifiedEpochMs;
  final String? artworkKey;
  final bool hasLyrics;
  final bool isInstrumental;
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
