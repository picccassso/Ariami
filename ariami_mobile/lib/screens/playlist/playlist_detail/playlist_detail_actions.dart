part of '../playlist_detail_screen.dart';

/// Handles user-initiated playlist, download, playback, and navigation actions.
abstract class _PlaylistDetailActionsState
    extends _PlaylistSongResolutionState {
  @override
  Future<void> _showOfflineCopyNoticeIfNeeded() async {
    if (!_isOfflineCopy ||
        !await _offlineCopyService.claimNotice('playlist', widget.playlistId) ||
        !mounted) {
      return;
    }

    final removeDownloads = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Offline copy kept'),
        content: const Text(
          'Just a heads up - this playlist has been deleted from the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep offline copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove downloads'),
          ),
        ],
      ),
    );

    if (removeDownloads != true || !mounted) return;
    await _downloadManager.deleteSongDownloads(_playlist?.songIds ?? const []);
    await _offlineCopyService.forgetPlaylist(widget.playlistId);
    await _libraryController.refreshOfflineCopyState();
    if (mounted) Navigator.of(context).pop();
  }

  /// Download all songs in the playlist that are not already downloaded.
  void _downloadPlaylist() {
    if (_connectionService.apiClient == null) {
      return;
    }

    final songsToDownload =
        _matchedSongs.where((s) => !_downloadedSongIds.contains(s.id)).toList();

    if (songsToDownload.isEmpty) {
      return;
    }

    final baseUrl = _connectionService.apiClient!.baseUrl;
    final playlist = _playlist;

    for (final song in songsToDownload) {
      final albumId = song.albumId ?? playlist?.songAlbumIds[song.id];
      String? albumName;
      String? albumArtist;

      if (albumId != null) {
        final albumInfo = _albumInfoMap[albumId];
        if (albumInfo != null) {
          albumName = albumInfo.name;
          albumArtist = albumInfo.artist;
        }
      }

      _downloadManager.downloadSong(
        songId: song.id,
        title: song.title,
        artist: song.artist,
        albumId: albumId,
        albumName: albumName,
        albumArtist: albumArtist,
        albumArt: albumId != null ? '$baseUrl/artwork/$albumId' : '',
        duration: song.duration,
        trackNumber: song.trackNumber,
        totalBytes: 0,
      );
    }
  }

  /// Prompt for confirmation, then delete this playlist's downloaded files.
  Future<void> _confirmRemoveDownloads() async {
    final playlistName = _playlist?.name ?? 'this playlist';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove downloads for "$playlistName"?'),
        content: const Text(
          'This deletes the downloaded files for this playlist from your '
          'device. You can download it again anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Remove',
              style:
                  TextStyle(color: Theme.of(dialogContext).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _downloadManager
        .deleteSongDownloads(_songs.map((s) => s.id).toList());
  }

  /// Cancel the active playlist batch and remove anything it downloaded.
  Future<void> _cancelPlaylistDownload() async {
    await _downloadManager
        .deleteSongDownloads(_songs.map((song) => song.id).toList());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Playlist download cancelled and removed'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Play all songs from playlist
  Future<void> _playAll() async {
    if (_songs.isEmpty) return;

    final isOffline = _shouldUseOfflineTracks;
    final songsToPlay = isOffline
        ? _songs.where((s) => _downloadedSongIds.contains(s.id)).toList()
        : _songs;

    if (songsToPlay.isEmpty) {
      return;
    }

    final songs =
        songsToPlay.map((s) => songModelToSong(s, _albumInfoMap)).toList();
    unawaited(_libraryController.markPlaylistPlayed(widget.playlistId));
    await _playbackManager.playSongs(songs, startIndex: 0);
  }

  /// Shuffle play all songs
  Future<void> _shuffleAll() async {
    if (_songs.isEmpty) return;

    final isOffline = _shouldUseOfflineTracks;
    final songsToPlay = isOffline
        ? _songs.where((s) => _downloadedSongIds.contains(s.id)).toList()
        : _songs;

    if (songsToPlay.isEmpty) {
      return;
    }

    final songs =
        songsToPlay.map((s) => songModelToSong(s, _albumInfoMap)).toList();
    unawaited(_libraryController.markPlaylistPlayed(widget.playlistId));
    await _playbackManager.playShuffled(songs);
  }

  /// Play a specific track
  Future<void> _playTrack(SongModel track, int index) async {
    final isOffline = _shouldUseOfflineTracks;
    final songsToPlay = isOffline
        ? _songs.where((s) => _downloadedSongIds.contains(s.id)).toList()
        : _songs;

    int startIndex;
    if (isOffline) {
      startIndex = songsToPlay.indexWhere((s) => s.id == track.id);
      if (startIndex == -1) startIndex = 0;
    } else {
      startIndex = index;
    }

    final songs =
        songsToPlay.map((s) => songModelToSong(s, _albumInfoMap)).toList();
    unawaited(_libraryController.markPlaylistPlayed(widget.playlistId));
    await _playbackManager.playSongs(songs, startIndex: startIndex);
  }

  /// Edit playlist name/description/image
  Future<void> _editPlaylist() async {
    if (_playlist == null) return;

    final result = await showEditPlaylistDialog(context, _playlist!);

    if (result != null && mounted) {
      await _playlistService.updatePlaylist(
        id: _playlist!.id,
        name: result.name,
        description: result.description,
        customImagePath: result.newImagePath,
        clearCustomImage: result.clearCustomImage,
      );
    }
  }

  /// Delete playlist with confirmation
  Future<void> _deletePlaylist() async {
    if (_playlist == null) return;

    final isImported = _playlistService.isImportedFromServer(_playlist!.id);
    final action = await showDeletePlaylistDialog(
      context,
      _playlist!,
      isImported: isImported,
    );

    if (action == DeletePlaylistAction.cancel || !mounted) return;

    _playlistService.removeListener(_onPlaylistsChanged);

    if (isImported) {
      await _playlistService.deleteImportedPlaylist(
        _playlist!.id,
        restoreServerVersion: action == DeletePlaylistAction.restore,
      );
    } else {
      await _playlistService.deletePlaylist(_playlist!.id);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Show modal bottom sheet with actions like Edit and Delete
  void _showMoreActions() {
    if (_playlist == null) return;

    showAriamiSheet<void>(
      context: context,
      header: AriamiSheetHeader(
        title: _playlist!.name,
        subtitle: '${_songs.length} song${_songs.length != 1 ? 's' : ''}',
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.purple[400],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.queue_music, color: Colors.white),
        ),
      ),
      items: [
        ListTile(
          leading: Icon(
            _libraryController.state.isPlaylistPinned(_playlist!.id)
                ? Icons.push_pin
                : Icons.push_pin_outlined,
          ),
          title: Text(
            _libraryController.state.isPlaylistPinned(_playlist!.id)
                ? 'Unpin Playlist'
                : 'Pin Playlist',
          ),
          onTap: () async {
            Navigator.pop(context);
            await _libraryController.togglePinPlaylist(_playlist!.id);
            if (mounted) setState(() {});
          },
        ),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Edit Playlist'),
          onTap: () {
            Navigator.pop(context);
            _editPlaylist();
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
          title: const Text(
            'Delete Playlist',
            style: TextStyle(color: Colors.red),
          ),
          onTap: () {
            Navigator.pop(context);
            _deletePlaylist();
          },
        ),
      ],
    );
  }

  /// Remove a song from playlist
  Future<void> _removeSong(String songId) async {
    await _playlistService.removeSongFromPlaylist(
      playlistId: widget.playlistId,
      songId: songId,
    );
  }

  /// Reorder songs in playlist
  void _onReorder(int oldIndex, int newIndex) {
    _playlistService.reorderSongs(
      playlistId: widget.playlistId,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  /// Navigate to add songs screen
  Future<void> _addSongs() async {
    List<SongModel> availableSongs = [];
    try {
      final allSongs = await _connectionService.libraryReadFacade.getSongs();
      final existingSongIds = _playlist?.songIds.toSet() ?? {};
      availableSongs =
          allSongs.where((song) => !existingSongIds.contains(song.id)).toList();
      availableSongs.sort((a, b) => a.title.compareTo(b.title));
    } catch (e) {
      print('[PlaylistDetailScreen] Error fetching songs: $e');
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddToPlaylistScreen(
          playlistId: widget.playlistId,
          playlistName: _playlist?.name ?? 'Playlist',
          availableSongs: availableSongs,
        ),
      ),
    );
  }
}
