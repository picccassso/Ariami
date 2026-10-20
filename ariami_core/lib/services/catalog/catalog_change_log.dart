import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// Shared `library_changes` feed helpers for [CatalogWriter] and the
/// LibraryManager's direct catalog sync, so both emit identical rows.

int readLatestChangeToken(Database database) {
  final rows = database.select(
    '''
SELECT COALESCE(MAX(token), 0) AS latest_token
FROM library_changes;
''',
  );
  return rows.first['latest_token'] as int;
}

void insertChangeEvent(
  Database database, {
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

String albumChangePayloadJson({
  required String id,
  required String title,
  required String artist,
  required String? coverArtKey,
  required int songCount,
  required int durationSeconds,
}) {
  return jsonEncode(<String, dynamic>{
    'id': id,
    'title': title,
    'artist': artist,
    'coverArt':
        coverArtKey == null ? null : '/api/artwork/${Uri.encodeComponent(id)}',
    'songCount': songCount,
    'duration': durationSeconds,
  });
}

String songChangePayloadJson({
  required String id,
  required String title,
  required String artist,
  required String? genre,
  required String? albumId,
  required int durationSeconds,
  required int? trackNumber,
  required bool hasLyrics,
}) {
  return jsonEncode(<String, dynamic>{
    'id': id,
    'title': title,
    'artist': artist,
    'genre': genre,
    'albumId': albumId,
    'duration': durationSeconds,
    'trackNumber': trackNumber,
    'hasLyrics': hasLyrics,
  });
}

String playlistChangePayloadJson({
  required String id,
  required String name,
  required int songCount,
  required int durationSeconds,
  required List<String> songIds,
}) {
  return jsonEncode(<String, dynamic>{
    'id': id,
    'name': name,
    'songCount': songCount,
    'duration': durationSeconds,
    'songIds': songIds,
  });
}

String playlistSongChangePayloadJson(
  String playlistId,
  String songId,
  int position,
) {
  return jsonEncode(<String, dynamic>{
    'playlistId': playlistId,
    'songId': songId,
    'position': position,
  });
}

class CatalogPlaylistSongKey implements Comparable<CatalogPlaylistSongKey> {
  const CatalogPlaylistSongKey({
    required this.playlistId,
    required this.songId,
    required this.position,
  });

  final String playlistId;
  final String songId;
  final int position;

  String get entityId => '$playlistId:$position';

  @override
  int compareTo(CatalogPlaylistSongKey other) {
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
    return other is CatalogPlaylistSongKey &&
        other.playlistId == playlistId &&
        other.songId == songId &&
        other.position == position;
  }

  @override
  int get hashCode => Object.hash(playlistId, songId, position);
}
