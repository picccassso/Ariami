part of '../library_manager.dart';

extension _LibraryManagerCatalogChangesPart on LibraryManager {
  int _readLatestTokenFromDatabase(Database database) {
    final rows = database.select(
      '''
SELECT COALESCE(MAX(token), 0) AS latest_token
FROM library_changes;
''',
    );
    return rows.first['latest_token'] as int;
  }

  void _insertLibraryChangeEvent({
    required Database database,
    required String entityType,
    required String entityId,
    required String op,
    String? payloadJson,
    required int occurredEpochMs,
  }) {
    database.execute(
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

  String _catalogAlbumPayloadJson(CatalogAlbumRecord record) {
    return jsonEncode(<String, dynamic>{
      'id': record.id,
      'title': record.title,
      'artist': record.artist,
      'coverArt': record.coverArtKey == null
          ? null
          : '/api/artwork/${Uri.encodeComponent(record.id)}',
      'songCount': record.songCount,
      'duration': record.durationSeconds,
    });
  }

  String _catalogSongPayloadJson(CatalogSongRecord record) {
    return jsonEncode(<String, dynamic>{
      'id': record.id,
      'title': record.title,
      'artist': record.artist,
      'albumId': record.albumId,
      'duration': record.durationSeconds,
      'trackNumber': record.trackNumber,
    });
  }

  String _catalogPlaylistPayloadJson(
    CatalogPlaylistRecord record, {
    required LibraryStructure updatedLibrary,
  }) {
    final playlist =
        updatedLibrary.folderPlaylists.where((p) => p.id == record.id).first;
    return jsonEncode(<String, dynamic>{
      'id': record.id,
      'name': record.name,
      'songCount': record.songCount,
      'duration': record.durationSeconds,
      'songIds': playlist.songIds,
    });
  }

  String _catalogPlaylistSongPayloadJson({
    required _CatalogPlaylistSongKey key,
    required int position,
  }) {
    return jsonEncode(<String, dynamic>{
      'playlistId': key.playlistId,
      'songId': key.songId,
      'position': position,
    });
  }

  String _catalogPlaylistSongDeletePayloadJson(_CatalogPlaylistSongKey key) {
    return jsonEncode(<String, dynamic>{
      'playlistId': key.playlistId,
      'songId': key.songId,
      'position': key.position,
    });
  }
}
