import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../models/song.dart';
import '../models/song_stats.dart';
import '../screens/main/library/library_controller.dart';
import '../services/api/connection_service.dart';
import '../services/offline/offline_playback_service.dart';
import '../services/playback_manager.dart';
import '../services/playlist_service.dart';
import '../services/stats/streaming_stats_service.dart';
import '../utils/responsive.dart';
import '../widgets/collection_play_buttons.dart';
import '../widgets/common/cached_artwork.dart';
import '../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../widgets/library/album_grid_item.dart';
import '../widgets/library/playlist_card.dart';
import '../widgets/library/song_list_item.dart';

/// Artist page: header with play/shuffle, the artist's top songs, their
/// albums, compilations they appear on, and the playlists their songs appear
/// on. Everything is derived from the in-memory library — no fetch.
class ArtistDetailScreen extends StatelessWidget {
  const ArtistDetailScreen({super.key, required this.artistName});

  final String artistName;

  @override
  Widget build(BuildContext context) {
    // The whole screen re-renders when the library, playlists or listening
    // stats change (all singletons are ChangeNotifiers).
    return ListenableBuilder(
      listenable: Listenable.merge([
        LibraryController(),
        PlaylistService(),
        StreamingStatsService(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final library = LibraryController();
    final albums = library.artistAlbums(artistName);
    final playlists = library.playlistsWithArtist(artistName);
    final tracks = library.artistTracks(artistName);
    final appearsOn = library.artistAppearsOn(artistName);
    final topTracks = _topTracks(tracks, StreamingStatsService().getAllStats());

    if (albums.isEmpty && playlists.isEmpty && tracks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(artistName)),
        body: Center(
          child: Text(
            "This artist isn't in your library.",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Pinned header showing the first album's artwork as the artist art.
          SliverAppBar(
            pinned: true,
            expandedHeight: detailHeaderHeight(context),
            title: Text(artistName),
            flexibleSpace: FlexibleSpaceBar(
              background: _ArtistHeaderArtwork(
                album: albums.isEmpty ? null : albums.first,
              ),
            ),
          ),

          // Info block: name, counts, play/shuffle.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artistName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_plural(albums.length, 'album')} • '
                    '${_plural(playlists.length, 'playlist')} • '
                    '${_plural(tracks.length, 'song')}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CollectionPlayButton(
                        sourceId: PlaybackManager.artistSource(artistName),
                        onPlay: tracks.isEmpty ? null : () => _playAll(tracks),
                      ),
                      const SizedBox(width: 12),
                      CollectionShuffleButton(
                        sourceId: PlaybackManager.artistSource(artistName),
                        onShuffle:
                            tracks.isEmpty ? null : () => _shuffleAll(tracks),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Top songs.
          if (topTracks.isNotEmpty) ...[
            const _SectionTitle('Top songs'),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildTrackItem(
                  context,
                  topTracks[index],
                  topTracks,
                  index,
                ),
                childCount: topTracks.length,
              ),
            ),
          ],

          // Albums.
          const _SectionTitle('Albums'),
          if (albums.isEmpty)
            const SliverToBoxAdapter(
              child: _EmptyLine('No albums by this artist in your library.'),
            )
          else
            _buildAlbumGrid(context, albums),

          // Compilations the artist appears on.
          if (appearsOn.isNotEmpty) ...[
            const _SectionTitle('Appears on'),
            _buildAlbumGrid(context, appearsOn),
          ],

          // Playlists.
          const _SectionTitle('Playlists'),
          if (playlists.isEmpty)
            const SliverToBoxAdapter(
              child: _EmptyLine('Not on any playlists yet.'),
            )
          else
            _buildPlaylistGrid(context, playlists),

          // Bottom padding for mini player + download bar.
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: getMiniPlayerScrollBottomPadding(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackItem(
    BuildContext context,
    SongModel track,
    List<SongModel> tracks,
    int index,
  ) {
    final state = LibraryController().state;
    final isOffline = OfflinePlaybackService().isOfflineModeEnabled;
    final isDownloaded = state.isSongDownloaded(track.id);
    final isCached = state.isSongCached(track.id);
    final album = _albumFor(track.albumId);

    return SongListItem(
      key: ValueKey('song-${track.id}'),
      song: track,
      onTap: (!isOffline || isDownloaded || isCached)
          ? () => _playTrack(track, index, tracks)
          : null,
      isDownloaded: isDownloaded,
      isCached: isCached,
      isAvailable: !isOffline || isDownloaded || isCached,
      isOfflineCopy: state.isOfflineCopySong(track.id),
      albumName: album?.title,
      albumArtist: album?.artist,
    );
  }

  Widget _buildAlbumGrid(BuildContext context, List<AlbumModel> albums) {
    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverGrid(
        gridDelegate: responsiveCardGridDelegate(),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final album = albums[index];
            return AlbumGridItem(
              key: ValueKey('album-${album.id}'),
              album: album,
              onTap: () =>
                  Navigator.of(context).pushNamed('/album', arguments: album),
            );
          },
          childCount: albums.length,
        ),
      ),
    );
  }

  Widget _buildPlaylistGrid(
    BuildContext context,
    List<PlaylistModel> playlists,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverGrid(
        gridDelegate: responsiveCardGridDelegate(),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final playlist = playlists[index];
            return PlaylistCard(
              key: ValueKey('playlist-${playlist.id}'),
              playlist: playlist,
              albumIds: playlist.songAlbumIds.values.toList(),
              onTap: () => Navigator.of(context)
                  .pushNamed('/playlist', arguments: playlist.id),
            );
          },
          childCount: playlists.length,
        ),
      ),
    );
  }

  // ============================================================================
  // PLAYBACK
  // ============================================================================

  /// Tracks that can be played in the current mode: everything online, or
  /// only the downloaded/cached ones in offline mode.
  List<SongModel> _availableTracks(List<SongModel> tracks) {
    if (!OfflinePlaybackService().isOfflineModeEnabled) return tracks;
    final state = LibraryController().state;
    return [
      for (final track in tracks)
        if (state.isSongDownloaded(track.id) || state.isSongCached(track.id))
          track,
    ];
  }

  Song _toSong(SongModel songModel) {
    final album = _albumFor(songModel.albumId);
    return Song(
      id: songModel.id,
      title: songModel.title,
      artist: songModel.artist,
      album: album?.title,
      albumId: songModel.albumId,
      albumArtist: album?.artist,
      duration: Duration(seconds: songModel.duration),
      filePath: songModel.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: songModel.trackNumber,
    );
  }

  void _playAll(List<SongModel> tracks) {
    final songs = [for (final track in _availableTracks(tracks)) _toSong(track)];
    if (songs.isEmpty) return;
    PlaybackManager().playSongs(
      songs,
      sourceId: PlaybackManager.artistSource(artistName),
    );
  }

  void _shuffleAll(List<SongModel> tracks) {
    final songs = [for (final track in _availableTracks(tracks)) _toSong(track)];
    if (songs.isEmpty) return;
    PlaybackManager().playShuffled(
      songs,
      sourceId: PlaybackManager.artistSource(artistName),
    );
  }

  void _playTrack(SongModel track, int index, List<SongModel> tracks) {
    List<SongModel> queueTracks;
    int startIndex;
    if (OfflinePlaybackService().isOfflineModeEnabled) {
      queueTracks = _availableTracks(tracks);
      startIndex = queueTracks.indexWhere((song) => song.id == track.id);
      if (startIndex == -1) startIndex = 0;
    } else {
      queueTracks = tracks;
      startIndex = index;
    }
    if (queueTracks.isEmpty) return;

    final songs = [
      for (final queueTrack in queueTracks) _toSong(queueTrack),
    ];
    PlaybackManager().playSongs(
      songs,
      startIndex: startIndex,
      sourceId: PlaybackManager.artistSource(artistName),
    );
  }

  /// Looks a track's album up in the in-memory library.
  AlbumModel? _albumFor(String? albumId) {
    if (albumId == null) return null;
    for (final album in LibraryController().state.albums) {
      if (album.id == albumId) return album;
    }
    return null;
  }

  String _plural(int count, String noun) =>
      '$count $noun${count == 1 ? '' : 's'}';
}

/// How many of an artist's songs the page lists — the full discography makes
/// the page one long list, so the section caps at the most-listened songs.
const int _topSongsLimit = 10;

/// Ranks [tracks] by listening stats and caps the list at [_topSongsLimit].
/// Unplayed songs keep their library order below the played ones, so the
/// section stays short but never empty.
List<SongModel> _topTracks(List<SongModel> tracks, List<SongStats> stats) {
  final statsById = <String, SongStats>{
    for (final stat in stats) stat.songId: stat,
  };
  final ranked = <({SongModel track, int plays, Duration listened, int index})>[
    for (var i = 0; i < tracks.length; i++)
      (
        track: tracks[i],
        plays: statsById[tracks[i].id]?.playCount ?? 0,
        listened: statsById[tracks[i].id]?.totalTime ?? Duration.zero,
        index: i,
      ),
  ]..sort((a, b) {
      if (a.plays != b.plays) return b.plays.compareTo(a.plays);
      if (a.listened != b.listened) return b.listened.compareTo(a.listened);
      // The sort isn't stable, so the library order breaks ties explicitly.
      return a.index.compareTo(b.index);
    });
  return [for (final entry in ranked.take(_topSongsLimit)) entry.track];
}

/// Static section title matching the library's section header text style.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Muted one-liner for an empty section.
class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Text(
        message,
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
    );
  }
}

/// First album's artwork as the artist header, or a plain placeholder.
class _ArtistHeaderArtwork extends StatelessWidget {
  const _ArtistHeaderArtwork({required this.album});

  final AlbumModel? album;

  @override
  Widget build(BuildContext context) {
    final apiClient = ConnectionService().apiClient;
    final artworkSize = isExpandedWidth(context) ? 280.0 : 200.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.2),
                Theme.of(context).scaffoldBackgroundColor,
              ],
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 40.0, bottom: 20.0),
            child: Container(
              width: artworkSize,
              height: artworkSize,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: album == null
                  ? _buildPlaceholder()
                  : CachedArtwork(
                      albumId: album!.id,
                      artworkUrl: apiClient != null
                          ? '${apiClient.baseUrl}/artwork/${album!.id}'
                          : null,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      fallback: _buildPlaceholder(),
                      fallbackIcon: Icons.music_note,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Icon(Icons.music_note, size: 80, color: Colors.white),
      ),
    );
  }
}
