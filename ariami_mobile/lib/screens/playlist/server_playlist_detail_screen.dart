import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../services/api/connection_service.dart';
import '../../services/playback_manager.dart';
import '../../services/playlist_service.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../main/library/library_controller.dart';
import 'add_to_playlist_screen.dart';
import 'utils/playlist_helpers.dart';
import 'widgets/widgets.dart';

class ServerPlaylistDetailScreen extends StatefulWidget {
  final String playlistId;

  const ServerPlaylistDetailScreen({
    super.key,
    required this.playlistId,
  });

  @override
  State<ServerPlaylistDetailScreen> createState() =>
      _ServerPlaylistDetailScreenState();
}

class _ServerPlaylistDetailScreenState
    extends State<ServerPlaylistDetailScreen> {
  final PlaylistService _playlistService = PlaylistService();
  final ConnectionService _connectionService = ConnectionService();
  final PlaybackManager _playbackManager = PlaybackManager();
  final LibraryController _libraryController = LibraryController();

  ServerPlaylistEffectiveState? _playlist;
  List<SongModel> _librarySongs = [];
  List<SongModel> _songs = [];
  bool _isLoading = true;
  bool _isReorderMode = false;
  String? _errorMessage;

  final Map<String, ({String name, String artist})> _albumInfoMap = {};

  @override
  void initState() {
    super.initState();
    _playlistService.addListener(_onPlaylistServiceChanged);
    unawaited(_loadPlaylist());
  }

  @override
  void dispose() {
    _playlistService.removeListener(_onPlaylistServiceChanged);
    super.dispose();
  }

  void _onPlaylistServiceChanged() {
    unawaited(_refreshResolvedPlaylist());
  }

  Future<void> _loadPlaylist() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _playlistService.loadServerPlaylistEdits();
      _librarySongs = await _connectionService.libraryReadFacade.getSongs();
      await _loadAlbumInfo();
      await _refreshResolvedPlaylist(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load playlist: $e';
      });
    }
  }

  Future<void> _refreshResolvedPlaylist({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    if (_librarySongs.isEmpty) {
      try {
        _librarySongs = await _connectionService.libraryReadFacade.getSongs();
      } catch (_) {
        _librarySongs = const <SongModel>[];
      }
    }

    final liveSongIds = _librarySongs.map((song) => song.id).toSet();
    final resolved = _playlistService.resolveServerPlaylist(
      widget.playlistId,
      liveSongIds: liveSongIds.isEmpty ? null : liveSongIds,
    );

    if (resolved == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Playlist not found';
        });
      }
      return;
    }

    final songsById = {for (final song in _librarySongs) song.id: song};
    final songs = resolved.songIds
        .map(
          (id) =>
              songsById[id] ??
              SongModel(
                id: id,
                title: 'Missing from library',
                artist: 'Unknown Artist',
                duration: 0,
              ),
        )
        .toList();

    if (!mounted) return;
    setState(() {
      _playlist = resolved;
      _songs = songs;
      _isLoading = false;
      _errorMessage = null;
    });
  }

  Future<void> _loadAlbumInfo() async {
    try {
      final albums = await _connectionService.libraryReadFacade.getAlbums();
      _albumInfoMap
        ..clear()
        ..addEntries(
          albums.map(
            (album) => MapEntry(
              album.id,
              (name: album.title, artist: album.artist),
            ),
          ),
        );
    } catch (_) {
      // Album names are only used for playback metadata; song playback still works.
    }
  }

  PlaylistModel _asPlaylistModel(ServerPlaylistEffectiveState playlist) {
    final now = DateTime.now();
    return PlaylistModel(
      id: playlist.base.id,
      name: playlist.name,
      description: playlist.hasEdit ? 'Edited server playlist' : null,
      songIds: playlist.songIds,
      createdAt: now,
      modifiedAt: now,
    );
  }

  Future<void> _playAll() async {
    if (_songs.isEmpty) return;
    final songs =
        _songs.map((song) => songModelToSong(song, _albumInfoMap)).toList();
    unawaited(_libraryController.markPlaylistPlayed(widget.playlistId));
    await _playbackManager.playSongs(songs, startIndex: 0);
  }

  Future<void> _shuffleAll() async {
    if (_songs.isEmpty) return;
    final songs =
        _songs.map((song) => songModelToSong(song, _albumInfoMap)).toList();
    unawaited(_libraryController.markPlaylistPlayed(widget.playlistId));
    await _playbackManager.playShuffled(songs);
  }

  Future<void> _playTrack(SongModel track, int index) async {
    final songs =
        _songs.map((song) => songModelToSong(song, _albumInfoMap)).toList();
    unawaited(_libraryController.markPlaylistPlayed(widget.playlistId));
    await _playbackManager.playSongs(songs, startIndex: index);
  }

  Future<void> _addSongs() async {
    final playlist = _playlist;
    if (playlist == null) return;

    if (_librarySongs.isEmpty) {
      _librarySongs = await _connectionService.libraryReadFacade.getSongs();
    }

    final existingSongIds = playlist.songIds.toSet();
    final availableSongs = _librarySongs
        .where((song) => !existingSongIds.contains(song.id))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddToPlaylistScreen(
          playlistId: widget.playlistId,
          playlistName: playlist.name,
          availableSongs: availableSongs,
          onAddSong: (song) => _playlistService.addSongToServerPlaylist(
            playlistId: widget.playlistId,
            songId: song.id,
          ),
          onRemoveSong: (song) => _playlistService.removeSongFromServerPlaylist(
            playlistId: widget.playlistId,
            songId: song.id,
          ),
        ),
      ),
    );
  }

  Future<void> _removeSong(String songId) {
    return _playlistService.removeSongFromServerPlaylist(
      playlistId: widget.playlistId,
      songId: songId,
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    unawaited(
      _playlistService.reorderServerPlaylist(
        playlistId: widget.playlistId,
        oldIndex: oldIndex,
        newIndex: newIndex,
      ),
    );
  }

  void _onReorderItem(int oldIndex, int newIndex) {
    final legacyNewIndex = newIndex > oldIndex ? newIndex + 1 : newIndex;
    _onReorder(oldIndex, legacyNewIndex);
  }

  Future<void> _renamePlaylist() async {
    final playlist = _playlist;
    if (playlist == null) return;

    final controller = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (name == null || !mounted) return;
    await _playlistService.renameServerPlaylist(
      playlistId: widget.playlistId,
      name: name,
    );
  }

  void _showMoreActions() {
    final playlist = _playlist;
    if (playlist == null) return;

    showAriamiSheet<void>(
      context: context,
      header: AriamiSheetHeader(
        title: playlist.name,
        subtitle: '${_songs.length} song${_songs.length == 1 ? '' : 's'}',
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.blue[500],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.folder, color: Colors.white),
        ),
      ),
      items: [
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Rename Playlist'),
          onTap: () {
            Navigator.pop(context);
            unawaited(_renamePlaylist());
          },
        ),
        if (playlist.hasEdit)
          ListTile(
            leading: const Icon(Icons.restore_rounded),
            title: const Text('Discard Edits'),
            onTap: () {
              Navigator.pop(context);
              unawaited(
                _playlistService.resetServerPlaylistEdit(widget.playlistId),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? ErrorState(
                  message: _errorMessage!,
                  onRetry: _loadPlaylist,
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final playlist = _playlist;
    if (playlist == null) {
      return const Center(child: Text('No playlist data'));
    }

    final baseUrl = _connectionService.apiClient?.baseUrl;
    final expandedArtHeight =
        MediaQuery.sizeOf(context).width.clamp(200.0, 600.0);
    final playlistModel = _asPlaylistModel(playlist);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: expandedArtHeight,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: PlaylistHeader(
              playlist: playlistModel,
              songs: _songs,
              baseUrl: baseUrl,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: PlaylistInfoSection(
            playlist: playlistModel,
            songs: _songs,
          ),
        ),
        SliverToBoxAdapter(
          child: PlaylistActionButtons(
            isPlaylistFullyDownloaded: false,
            hasSongs: _songs.isNotEmpty,
            canReorder: _songs.length > 1,
            isReorderMode: _isReorderMode,
            onPlay: _playAll,
            onShuffle: _shuffleAll,
            onToggleReorder: () =>
                setState(() => _isReorderMode = !_isReorderMode),
            onAddSongs: _addSongs,
            onMoreActions: _showMoreActions,
          ),
        ),
        if (_songs.isEmpty)
          const SliverToBoxAdapter(child: EmptyPlaylistState())
        else if (_isReorderMode)
          SliverReorderableList(
            itemCount: _songs.length,
            onReorderItem: _onReorderItem,
            itemBuilder: (context, index) {
              final song = _songs[index];
              return ReorderListItem(
                key: ValueKey(song.id),
                song: song,
                index: index,
                onRemove: () => _removeSong(song.id),
              );
            },
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = _songs[index];
                return SongListItem(
                  song: song,
                  index: index,
                  isAvailable: song.title != 'Missing from library',
                  isDownloaded: false,
                  connectionService: _connectionService,
                  albumName: song.albumId == null
                      ? null
                      : _albumInfoMap[song.albumId]?.name,
                  albumArtist: song.albumId == null
                      ? null
                      : _albumInfoMap[song.albumId]?.artist,
                  onTap: () => _playTrack(song, index),
                  onRemove: () => _removeSong(song.id),
                );
              },
              childCount: _songs.length,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
      ],
    );
  }
}
