part of 'playlist_service.dart';

extension _PlaylistServiceLikedSongsImpl on PlaylistService {
  Future<PlaylistModel> _getLikedSongsPlaylistImpl() async {
    if (!_isLoaded) {
      await loadPlaylists();
    }

    final existingPlaylist = getPlaylist(PlaylistService.likedSongsId);
    if (existingPlaylist != null) {
      return existingPlaylist;
    }

    final now = DateTime.now();
    final likedSongsPlaylist = PlaylistModel(
      id: PlaylistService.likedSongsId,
      name: 'Liked Songs',
      description: 'Your favorite tracks',
      songIds: [],
      createdAt: now,
      modifiedAt: now,
    );

    _playlists.insert(0, likedSongsPlaylist);
    await _savePlaylists();
    _notifyListeners();

    return likedSongsPlaylist;
  }

  bool _isLikedSongImpl(String songId) {
    if (!_isLoaded) return false;

    final likedPlaylist = getPlaylist(PlaylistService.likedSongsId);
    if (likedPlaylist == null) return false;

    return likedPlaylist.songIds.contains(songId);
  }

  Future<void> _toggleLikedSongImpl(
    String songId,
    String? albumId, {
    String? title,
    String? artist,
    int? duration,
  }) async {
    await getLikedSongsPlaylist();

    if (isLikedSong(songId)) {
      await removeSongFromPlaylist(
        playlistId: PlaylistService.likedSongsId,
        songId: songId,
      );
    } else {
      await addSongToPlaylist(
        playlistId: PlaylistService.likedSongsId,
        songId: songId,
        albumId: albumId,
        title: title,
        artist: artist,
        duration: duration,
      );
    }
  }
}
