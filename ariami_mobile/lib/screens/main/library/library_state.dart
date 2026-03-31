import 'package:flutter/foundation.dart';
import '../../../models/api_models.dart';
import '../../../models/song.dart';

/// Immutable state class for the library screen.
/// Contains all the data needed to render the library UI.
@immutable
class LibraryState {
  /// Online mode state from server API
  final List<AlbumModel> albums;
  final List<SongModel> songs;

  /// Offline mode state built from downloads
  final List<Song> offlineSongs;
  final bool isOfflineMode;

  /// Loading and error states
  final bool isLoading;
  final String? errorMessage;

  /// UI preferences
  final bool isGridView;
  final bool albumsExpanded;
  final bool songsExpanded;
  final bool isMixedMode;

  /// Download/cache tracking
  final bool showDownloadedOnly;
  final Set<String> downloadedSongIds;
  final Set<String> cachedSongIds;
  final Set<String> albumsWithDownloads;
  final Set<String> fullyDownloadedAlbumIds;
  final Set<String> playlistsWithDownloads;
  final Map<String, DateTime> itemLastAccessedAt;

  /// Pinned library items (keys like "album:$id" or "playlist:$id")
  final Set<String> pinnedItemIds;

  const LibraryState({
    this.albums = const [],
    this.songs = const [],
    this.offlineSongs = const [],
    this.isOfflineMode = false,
    this.isLoading = true,
    this.errorMessage,
    this.isGridView = true,
    this.albumsExpanded = true,
    this.songsExpanded = false,
    this.isMixedMode = false,
    this.showDownloadedOnly = false,
    this.downloadedSongIds = const {},
    this.cachedSongIds = const {},
    this.albumsWithDownloads = const {},
    this.fullyDownloadedAlbumIds = const {},
    this.playlistsWithDownloads = const {},
    this.itemLastAccessedAt = const {},
    this.pinnedItemIds = const {},
  });

  /// Creates a copy of this state with the given fields replaced
  LibraryState copyWith({
    List<AlbumModel>? albums,
    List<SongModel>? songs,
    List<Song>? offlineSongs,
    bool? isOfflineMode,
    bool? isLoading,
    String? errorMessage,
    bool? isGridView,
    bool? albumsExpanded,
    bool? songsExpanded,
    bool? isMixedMode,
    bool? showDownloadedOnly,
    Set<String>? downloadedSongIds,
    Set<String>? cachedSongIds,
    Set<String>? albumsWithDownloads,
    Set<String>? fullyDownloadedAlbumIds,
    Set<String>? playlistsWithDownloads,
    Map<String, DateTime>? itemLastAccessedAt,
    Set<String>? pinnedItemIds,
    bool clearError = false,
  }) {
    return LibraryState(
      albums: albums ?? this.albums,
      songs: songs ?? this.songs,
      offlineSongs: offlineSongs ?? this.offlineSongs,
      isOfflineMode: isOfflineMode ?? this.isOfflineMode,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isGridView: isGridView ?? this.isGridView,
      albumsExpanded: albumsExpanded ?? this.albumsExpanded,
      songsExpanded: songsExpanded ?? this.songsExpanded,
      isMixedMode: isMixedMode ?? this.isMixedMode,
      showDownloadedOnly: showDownloadedOnly ?? this.showDownloadedOnly,
      downloadedSongIds: downloadedSongIds ?? this.downloadedSongIds,
      cachedSongIds: cachedSongIds ?? this.cachedSongIds,
      albumsWithDownloads: albumsWithDownloads ?? this.albumsWithDownloads,
      fullyDownloadedAlbumIds:
          fullyDownloadedAlbumIds ?? this.fullyDownloadedAlbumIds,
      playlistsWithDownloads:
          playlistsWithDownloads ?? this.playlistsWithDownloads,
      itemLastAccessedAt: itemLastAccessedAt ?? this.itemLastAccessedAt,
      pinnedItemIds: pinnedItemIds ?? this.pinnedItemIds,
    );
  }

  /// Returns true if the library is empty (no playlists, albums, or songs)
  bool get isLibraryEmpty {
    final songsEmpty = isOfflineMode ? offlineSongs.isEmpty : songs.isEmpty;
    return albums.isEmpty && songsEmpty;
  }

  /// Returns the list of albums to show based on download filter
  List<AlbumModel> get albumsToShow {
    if (!showDownloadedOnly) return albums;
    return albums
        .where((album) => albumsWithDownloads.contains(album.id))
        .toList();
  }

  /// Returns the list of online songs to show based on download filter
  List<SongModel> get onlineSongsToShow {
    if (!showDownloadedOnly) return songs;
    return songs.where((song) => downloadedSongIds.contains(song.id)).toList();
  }

  /// Returns true if the given album has downloaded songs
  bool hasAlbumDownloads(String albumId) =>
      albumsWithDownloads.contains(albumId);

  /// Returns true if the given album is fully downloaded
  bool isAlbumFullyDownloaded(String albumId) =>
      fullyDownloadedAlbumIds.contains(albumId);

  /// Returns true if the given song is downloaded
  bool isSongDownloaded(String songId) => downloadedSongIds.contains(songId);

  /// Returns true if the given song is cached
  bool isSongCached(String songId) => cachedSongIds.contains(songId);

  /// Returns true if the given playlist has downloaded songs
  bool hasPlaylistDownloads(String playlistId) =>
      playlistsWithDownloads.contains(playlistId);

  DateTime? lastAccessedForAlbum(String albumId) =>
      itemLastAccessedAt['album:$albumId'];

  DateTime? lastAccessedForPlaylist(String playlistId) =>
      itemLastAccessedAt['playlist:$playlistId'];

  bool isAlbumPinned(String albumId) =>
      pinnedItemIds.contains('album:$albumId');

  bool isPlaylistPinned(String playlistId) =>
      pinnedItemIds.contains('playlist:$playlistId');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LibraryState &&
        listEquals(other.albums, albums) &&
        listEquals(other.songs, songs) &&
        listEquals(other.offlineSongs, offlineSongs) &&
        other.isOfflineMode == isOfflineMode &&
        other.isLoading == isLoading &&
        other.errorMessage == errorMessage &&
        other.isGridView == isGridView &&
        other.albumsExpanded == albumsExpanded &&
        other.songsExpanded == songsExpanded &&
        other.isMixedMode == isMixedMode &&
        other.showDownloadedOnly == showDownloadedOnly &&
        setEquals(other.downloadedSongIds, downloadedSongIds) &&
        setEquals(other.cachedSongIds, cachedSongIds) &&
        setEquals(other.albumsWithDownloads, albumsWithDownloads) &&
        setEquals(other.fullyDownloadedAlbumIds, fullyDownloadedAlbumIds) &&
        setEquals(other.playlistsWithDownloads, playlistsWithDownloads) &&
        mapEquals(other.itemLastAccessedAt, itemLastAccessedAt) &&
        setEquals(other.pinnedItemIds, pinnedItemIds);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(albums),
        Object.hashAll(songs),
        Object.hashAll(offlineSongs),
        isOfflineMode,
        isLoading,
        errorMessage,
        isGridView,
        albumsExpanded,
        songsExpanded,
        isMixedMode,
        showDownloadedOnly,
        Object.hashAll(downloadedSongIds),
        Object.hashAll(cachedSongIds),
        Object.hashAll(albumsWithDownloads),
        Object.hashAll(fullyDownloadedAlbumIds),
        Object.hashAll(playlistsWithDownloads),
        Object.hashAllUnordered(itemLastAccessedAt.entries),
        Object.hashAll(pinnedItemIds),
      );

  @override
  String toString() {
    return 'LibraryState(albums: ${albums.length}, songs: ${songs.length}, '
        'offlineSongs: ${offlineSongs.length}, isOfflineMode: $isOfflineMode, '
        'isLoading: $isLoading, errorMessage: $errorMessage, '
        'isGridView: $isGridView, albumsExpanded: $albumsExpanded, '
        'songsExpanded: $songsExpanded, isMixedMode: $isMixedMode, '
        'showDownloadedOnly: $showDownloadedOnly, '
        'downloadedSongIds: ${downloadedSongIds.length}, '
        'cachedSongIds: ${cachedSongIds.length}, '
        'pinnedItemIds: ${pinnedItemIds.length}, '
        'itemLastAccessedAt: ${itemLastAccessedAt.length})';
  }
}

/// Extension methods for Set comparison
bool setEquals<T>(Set<T>? a, Set<T>? b) {
  if (a == null) return b == null;
  if (b == null) return false;
  return a.length == b.length && a.containsAll(b);
}
