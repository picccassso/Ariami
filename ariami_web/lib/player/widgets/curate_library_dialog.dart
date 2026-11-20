import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:ariami_core/services/search/search.dart';
import 'package:ariami_core/services/playlists/created_playlist_id.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'curation/library_curation_picker_dialog.dart';
import '../models/player_models.dart';
import '../services/library_controller.dart';

/// Opens the 4-tab curation dialog with thumbnails for the signed-in
/// listener's own library in the Desktop Music Player.
Future<UserLibraryCuration?> showPlayerLibraryCurationDialog(
  BuildContext context, {
  LibraryCurationMode? initialModeOverride,
}) {
  final library = context.read<LibraryController>();
  return showLibraryCurationPickerDialog(
    context,
    title: 'Curate My Library',
    initialModeOverride: initialModeOverride,
    artworkClient: library.client,
    artistImageVersionOf: library.artistImageVersion,
    playlistImageVersionOf: library.playlistImageVersion,
    loadBundle: () async {
      if (!library.curationLoaded) {
        await library.refreshCuration();
      }
      final albums = library.rawAlbums
          .map(
            (a) => CurationCatalogAlbum(
              id: a.id,
              title: a.title,
              artist: a.artist,
              songCount: a.songCount,
            ),
          )
          .toList(growable: false);
      final playlists = library.rawServerPlaylists
          .where((p) => !isAccountOwnedPlaylistId(p.id))
          .map(
            (p) => CurationCatalogPlaylist(
              id: p.id,
              name: p.name,
              songCount: p.songCount,
            ),
          )
          .toList(growable: false);
      final standaloneSongs = library.rawSongs
          .where((s) => s.albumId == null || s.albumId!.trim().isEmpty)
          .map(_trackToCatalogSong)
          .toList(growable: false);
      return (
        curation: library.curation,
        albums: albums,
        playlists: playlists,
        standaloneSongs: standaloneSongs,
      );
    },
    loadAllSongs: () =>
        library.rawSongs.map(_trackToCatalogSong).toList(growable: false),
    loadPlaylistAlbumIds: () {
      final songAlbumIdById = <String, String>{
        for (final song in library.rawSongs)
          if (song.albumId != null && song.albumId!.trim().isNotEmpty)
            song.id: song.albumId!,
      };
      final map = <String, List<String>>{};
      for (final playlist in library.rawServerPlaylists) {
        if (isAccountOwnedPlaylistId(playlist.id)) continue;
        final albumIds = <String>[];
        for (final songId in playlist.songIds) {
          final albumId = songAlbumIdById[songId];
          if (albumId != null && !albumIds.contains(albumId)) {
            albumIds.add(albumId);
            if (albumIds.length == 4) break;
          }
        }
        map[playlist.id] = albumIds;
      }
      return map;
    },
    loadAlbumSongs: (albumId) async =>
        library.albumTracks(albumId).map(_trackToCatalogSong).toList(),
    searchAllSongs: (query) async {
      final parsed = SearchQuery.parse(query);
      if (parsed.isEmpty) return const <CurationCatalogSong>[];
      final results = LibrarySearchEngine.rank<Track>(
        parsed,
        library.rawSongs,
        (s) => [
          SearchField(s.title, isPrimary: true),
          SearchField(s.artist),
          if (s.albumTitle != null) SearchField(s.albumTitle!),
        ],
        limit: 80,
      );
      return results.map(_trackToCatalogSong).toList(growable: false);
    },
    onSave: (mode, rules) async {
      await library.saveCuration(
        mode: mode,
        rules: rules,
        onboardingCompleted: true,
      );
      return library.curation;
    },
  );
}

CurationCatalogSong _trackToCatalogSong(Track track) {
  return CurationCatalogSong(
    id: track.id,
    title: track.title,
    artist: track.artist,
    albumId: track.albumId,
    albumTitle: track.albumTitle,
    durationSeconds: track.durationSeconds,
    trackNumber: track.trackNumber,
  );
}
