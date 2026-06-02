import 'package:shared_preferences/shared_preferences.dart';

import '../../models/download_task.dart';

/// Tracks explicit downloads whose server-side library items were removed.
///
/// Streaming cache entries are intentionally excluded: offline copies only
/// represent downloads the user explicitly chose to keep on the device.
class OfflineCopyService {
  static const _retainedSongIdsKey = 'offline_copy_song_ids';
  static const _retainedAlbumIdsKey = 'offline_copy_album_ids';
  static const _retainedPlaylistIdsKey = 'offline_copy_playlist_ids';
  static const _shownNoticeIdsKey = 'offline_copy_shown_notice_ids';

  static final OfflineCopyService _instance = OfflineCopyService._internal();
  factory OfflineCopyService() => _instance;
  OfflineCopyService._internal();

  final Set<String> _retainedSongIds = {};
  final Set<String> _retainedAlbumIds = {};
  final Set<String> _retainedPlaylistIds = {};
  final Set<String> _shownNoticeIds = {};
  bool _isInitialized = false;

  Set<String> get retainedSongIds => Set.unmodifiable(_retainedSongIds);
  Set<String> get retainedAlbumIds => Set.unmodifiable(_retainedAlbumIds);
  Set<String> get retainedPlaylistIds => Set.unmodifiable(_retainedPlaylistIds);

  bool isRetainedSong(String songId) => _retainedSongIds.contains(songId);
  bool isRetainedAlbum(String albumId) => _retainedAlbumIds.contains(albumId);
  bool isRetainedPlaylist(String playlistId) =>
      _retainedPlaylistIds.contains(playlistId);

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    final prefs = await SharedPreferences.getInstance();
    _retainedSongIds.addAll(prefs.getStringList(_retainedSongIdsKey) ?? []);
    _retainedAlbumIds.addAll(prefs.getStringList(_retainedAlbumIdsKey) ?? []);
    _retainedPlaylistIds
        .addAll(prefs.getStringList(_retainedPlaylistIdsKey) ?? []);
    _shownNoticeIds.addAll(prefs.getStringList(_shownNoticeIdsKey) ?? []);
  }

  Future<void> reconcileAlbums({
    required Iterable<DownloadTask> tasks,
    required Set<String> serverSongIds,
    required Set<String> serverAlbumIds,
  }) async {
    await initialize();

    final completedTasks =
        tasks.where((task) => task.status == DownloadStatus.completed).toList();
    final retainedAlbumIds = completedTasks
        .where((task) =>
            task.albumId != null && !serverAlbumIds.contains(task.albumId))
        .map((task) => task.albumId!)
        .toSet();
    final retainedSongIds = completedTasks
        .where((task) =>
            !serverSongIds.contains(task.songId) ||
            (task.albumId != null && retainedAlbumIds.contains(task.albumId)))
        .map((task) => task.songId)
        .toSet();

    _retainedSongIds
      ..clear()
      ..addAll(retainedSongIds);
    _retainedAlbumIds
      ..clear()
      ..addAll(retainedAlbumIds);
    await _persist();
  }

  Future<void> reconcilePlaylists(Set<String> retainedPlaylistIds) async {
    await initialize();
    _retainedPlaylistIds
      ..clear()
      ..addAll(retainedPlaylistIds);
    await _persist();
  }

  Future<void> forgetAlbum(String albumId, Iterable<String> songIds) async {
    await initialize();
    _retainedAlbumIds.remove(albumId);
    _retainedSongIds.removeAll(songIds);
    await _persist();
  }

  Future<void> forgetPlaylist(String playlistId) async {
    await initialize();
    _retainedPlaylistIds.remove(playlistId);
    await _persist();
  }

  void resetToDefaults() {
    _retainedSongIds.clear();
    _retainedAlbumIds.clear();
    _retainedPlaylistIds.clear();
    _shownNoticeIds.clear();
    _isInitialized = false;
  }

  /// Returns true only the first time a retained item is opened.
  Future<bool> claimNotice(String itemType, String itemId) async {
    await initialize();
    final noticeId = '$itemType:$itemId';
    if (!_shownNoticeIds.add(noticeId)) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_shownNoticeIdsKey, _shownNoticeIds.toList());
    return true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_retainedSongIdsKey, _retainedSongIds.toList());
    await prefs.setStringList(_retainedAlbumIdsKey, _retainedAlbumIds.toList());
    await prefs.setStringList(
      _retainedPlaylistIdsKey,
      _retainedPlaylistIds.toList(),
    );
  }
}
