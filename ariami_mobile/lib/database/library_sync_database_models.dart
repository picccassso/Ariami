part of 'library_sync_database.dart';

class LibrarySyncState {
  final int lastAppliedToken;
  final bool bootstrapComplete;
  final int lastSyncEpochMs;

  const LibrarySyncState({
    required this.lastAppliedToken,
    required this.bootstrapComplete,
    required this.lastSyncEpochMs,
  });
}

class LibraryAlbumRow {
  final String id;
  final String title;
  final String artist;
  final String? coverArt;
  final int songCount;
  final int duration;
  final bool isDeleted;
  final DateTime? createdAt;
  final DateTime? modifiedAt;

  const LibraryAlbumRow({
    required this.id,
    required this.title,
    required this.artist,
    this.coverArt,
    required this.songCount,
    required this.duration,
    this.isDeleted = false,
    this.createdAt,
    this.modifiedAt,
  });
}

class LibrarySongRow {
  final String id;
  final String title;
  final String artist;
  final String? albumId;
  final int duration;
  final int? trackNumber;
  final bool isDeleted;

  const LibrarySongRow({
    required this.id,
    required this.title,
    required this.artist,
    this.albumId,
    required this.duration,
    this.trackNumber,
    this.isDeleted = false,
  });
}

class LibraryPlaylistRow {
  final String id;
  final String name;
  final int songCount;
  final int duration;
  final bool isDeleted;

  const LibraryPlaylistRow({
    required this.id,
    required this.name,
    required this.songCount,
    required this.duration,
    this.isDeleted = false,
  });
}

class LibraryPlaylistSongRow {
  final String playlistId;
  final String songId;
  final int position;
  final bool isDeleted;

  const LibraryPlaylistSongRow({
    required this.playlistId,
    required this.songId,
    required this.position,
    this.isDeleted = false,
  });
}

class PlaylistMembershipBackfillIssue {
  const PlaylistMembershipBackfillIssue({
    required this.playlistId,
    required this.playlistName,
    required this.expectedSongCount,
    required this.activeSongCount,
  });

  final String playlistId;
  final String playlistName;
  final int expectedSongCount;
  final int activeSongCount;
}

class AlbumSongCountIssue {
  const AlbumSongCountIssue({
    required this.albumId,
    required this.albumTitle,
    required this.expectedSongCount,
    required this.activeSongCount,
  });

  final String albumId;
  final String albumTitle;
  final int expectedSongCount;
  final int activeSongCount;
}
