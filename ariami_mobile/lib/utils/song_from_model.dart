import '../models/api_models.dart';
import '../models/song.dart';

/// Builds a playable [Song] from a [SongModel]. [albumId] defaults to the
/// model's own when not overridden.
Song songFromModel(
  SongModel model, {
  String? album,
  String? albumId,
  String? albumArtist,
}) {
  return Song(
    id: model.id,
    title: model.title,
    artist: model.artist,
    genre: model.genre,
    album: album,
    albumId: albumId ?? model.albumId,
    albumArtist: albumArtist,
    duration: Duration(seconds: model.duration),
    trackNumber: model.trackNumber,
    filePath: model.id, // Use song ID as placeholder
    fileSize: 0,
    modifiedTime: DateTime.now(),
    hasLyrics: model.hasLyrics,
    isInstrumental: model.isInstrumental,
  );
}
