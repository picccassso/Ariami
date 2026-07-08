import 'package:test/test.dart';

import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/album_builder.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';

/// Pins the scanner/album/playlist semantics after the Pass-1 playlist
/// correctness fixes (2026-07):
///
/// - [PLAYLIST] folder membership is ADDITIVE: tracks inside playlist
///   folders still join album grouping (or become standalone) normally.
/// - The [PLAYLIST] marker is case-insensitive but must start the name.
/// - Folder playlist entries use deterministic path-sorted order in both
///   the full-scan and incremental rebuild paths.
///
/// If one of these fails after a scanner change, the behaviour shift was
/// real — decide whether it was intended before "fixing" the test.
void main() {
  SongMetadata song({
    required String path,
    String? title,
    String? artist,
    String? albumArtist,
    String? album,
    int? trackNumber,
    int? duration,
  }) {
    return SongMetadata(
      filePath: path,
      title: title,
      artist: artist,
      albumArtist: albumArtist,
      album: album,
      trackNumber: trackNumber,
      duration: duration,
    );
  }

  group('[PLAYLIST] marker semantics (FolderPlaylist)', () {
    test('marker is case-insensitive', () {
      expect(FolderPlaylist.isPlaylistFolder('[PLAYLIST] Gym'), isTrue);
      expect(FolderPlaylist.isPlaylistFolder('[playlist] Gym'), isTrue);
      expect(FolderPlaylist.isPlaylistFolder('[Playlist] Gym'), isTrue);
      expect(FolderPlaylist.isPlaylistFolder('[PlAyLiSt] Gym'), isTrue);
    });

    test('marker must be at the very start of the folder name', () {
      expect(FolderPlaylist.isPlaylistFolder('Gym [PLAYLIST]'), isFalse);
      expect(FolderPlaylist.isPlaylistFolder(' [PLAYLIST] Gym'), isFalse);
      expect(FolderPlaylist.isPlaylistFolder('[PLAYLIST]Gym'), isTrue);
    });

    test('display name strips the marker (any case) and trims whitespace',
        () {
      expect(FolderPlaylist.extractName('[PLAYLIST] Summer Vibes'),
          'Summer Vibes');
      expect(FolderPlaylist.extractName('[playlist] Summer Vibes'),
          'Summer Vibes');
      expect(FolderPlaylist.extractName('[Playlist] Gym'), 'Gym');
      expect(FolderPlaylist.extractName('[PLAYLIST]Gym'), 'Gym');
      // Non-marker names pass through unchanged.
      expect(FolderPlaylist.extractName('Road Trip'), 'Road Trip');
    });
  });

  group('detectPlaylistFolderPath', () {
    test('detects nearest marked ancestor, including nested subfolders', () {
      expect(
        detectPlaylistFolderPath('/music/[PLAYLIST] Gym/song.mp3'),
        '/music/[PLAYLIST] Gym',
      );
      // Files nested deeper inside a playlist folder still belong to it.
      expect(
        detectPlaylistFolderPath('/music/[PLAYLIST] Gym/sub/deeper/song.mp3'),
        '/music/[PLAYLIST] Gym',
      );
      // Lowercase marker works too.
      expect(
        detectPlaylistFolderPath('/music/[playlist] Gym/song.mp3'),
        '/music/[playlist] Gym',
      );
    });

    test('normal folders never become playlists', () {
      expect(detectPlaylistFolderPath('/music/Gym/song.mp3'), isNull);
      expect(detectPlaylistFolderPath('/music/Road Trip/song.mp3'), isNull);
    });
  });

  group('AlbumBuilder current grouping rules', () {
    test('albums come from tags only — folder path is never a grouping key',
        () {
      // Same album tag scattered across unrelated folders still merges.
      final library = AlbumBuilder().buildLibrary([
        song(
            path: '/a/x.mp3',
            title: 'One',
            artist: 'A',
            album: 'Same Album',
            trackNumber: 1),
        song(
            path: '/completely/elsewhere/y.mp3',
            title: 'Two',
            artist: 'A',
            album: 'Same Album',
            trackNumber: 2),
      ]);
      expect(library.albums.length, 1);
      expect(library.albums.values.single.songs.length, 2);
    });

    test('track numbers are not required for album creation', () {
      final library = AlbumBuilder().buildLibrary([
        song(path: '/a/1.mp3', title: 'One', artist: 'A', album: 'Album'),
        song(path: '/a/2.mp3', title: 'Two', artist: 'A', album: 'Album'),
      ]);
      expect(library.albums.length, 1);
    });

    test('missing album tag means standalone, never an album', () {
      final library = AlbumBuilder().buildLibrary([
        song(path: '/gym/1.mp3', title: 'One', artist: 'A'),
        song(path: '/gym/2.mp3', title: 'Two', artist: 'B'),
      ]);
      expect(library.albums, isEmpty);
      expect(library.standaloneSongs.length, 2);
    });

    test('a single track with album tags stays standalone (2-song minimum)',
        () {
      final library = AlbumBuilder().buildLibrary([
        song(path: '/x.mp3', title: 'Only', artist: 'A', album: 'Solo Album'),
      ]);
      expect(library.albums, isEmpty);
      expect(library.standaloneSongs.length, 1);
    });

    test('same album title under different artists stays split', () {
      final library = AlbumBuilder().buildLibrary([
        song(path: '/1.mp3', title: 'S1', artist: 'Artist A', album: 'Greatest Hits'),
        song(path: '/2.mp3', title: 'S2', artist: 'Artist A', album: 'Greatest Hits'),
        song(path: '/3.mp3', title: 'S3', artist: 'Artist B', album: 'Greatest Hits'),
        song(path: '/4.mp3', title: 'S4', artist: 'Artist B', album: 'Greatest Hits'),
      ]);
      expect(library.albums.length, 2);
    });

    test('Various Artists album artist groups a compilation into one album',
        () {
      final library = AlbumBuilder().buildLibrary([
        song(
            path: '/now/1.mp3',
            title: 'S1',
            artist: 'Artist A',
            albumArtist: 'Various Artists',
            album: 'Now Album',
            trackNumber: 1),
        song(
            path: '/now/2.mp3',
            title: 'S2',
            artist: 'Artist B',
            albumArtist: 'Various Artists',
            album: 'Now Album',
            trackNumber: 2),
      ]);
      expect(library.albums.length, 1);
      final album = library.albums.values.single;
      expect(album.artist, 'Various Artists');
      expect(album.isCompilation, isTrue);
    });

    test(
        'compilation with NO album artist splits per track artist '
        '(each side below the 2-song threshold becomes standalone)', () {
      final library = AlbumBuilder().buildLibrary([
        song(
            path: '/now/1.mp3',
            title: 'S1',
            artist: 'Artist A',
            album: 'Now Album',
            trackNumber: 1),
        song(
            path: '/now/2.mp3',
            title: 'S2',
            artist: 'Artist B',
            album: 'Now Album',
            trackNumber: 2),
      ]);
      expect(library.albums, isEmpty);
      expect(library.standaloneSongs.length, 2);
    });
  });

  group('album/playlist interaction (buildLibraryWithPlaylists)', () {
    // The "Mercy" scenario from the audit brief.
    final mercyInPlaylistFolder = song(
      path: '/music/[PLAYLIST] Gym Playlist/Kanye West - Mercy.mp3',
      title: 'Mercy',
      artist: 'Kanye West, Big Sean, Pusha T, 2 Chainz',
      albumArtist: 'Various Artists',
      album: 'Cruel Summer',
      trackNumber: 5,
    );
    final otherCruelSummerTrack = song(
      path: '/music/Various Artists/Cruel Summer/01 To The World.mp3',
      title: 'To The World',
      artist: 'Kanye West, R. Kelly',
      albumArtist: 'Various Artists',
      album: 'Cruel Summer',
      trackNumber: 1,
    );

    test(
        'a track inside a [PLAYLIST] folder is additive: it joins album '
        'grouping AND appears in the folder playlist', () {
      final library = buildLibraryWithPlaylists(
        allSongs: [mercyInPlaylistFolder, otherCruelSummerTrack],
        existingPlaylists: const [],
      );

      // Both Cruel Summer tracks are album-eligible -> album exists.
      expect(library.albums.length, 1);
      final album = library.albums.values.single;
      expect(album.title, 'Cruel Summer');
      expect(album.songs.map((s) => s.filePath),
          contains(mercyInPlaylistFolder.filePath));

      // The playlist exists too and references the same song ID.
      expect(library.folderPlaylists.length, 1);
      expect(library.folderPlaylists.single.name, 'Gym Playlist');
      expect(
        library.folderPlaylists.single.songIds,
        [defaultGenerateSongId(mercyInPlaylistFolder.filePath)],
      );

      // The track is NOT forced standalone.
      expect(
        library.standaloneSongs.map((s) => s.filePath),
        isNot(contains(mercyInPlaylistFolder.filePath)),
      );
    });

    test(
        'the same track in a normal folder (no marker) joins the album and '
        'no playlist is created', () {
      final mercyInPlainFolder = song(
        path: '/music/Gym Playlist/Kanye West - Mercy.mp3',
        title: 'Mercy',
        artist: 'Kanye West, Big Sean, Pusha T, 2 Chainz',
        albumArtist: 'Various Artists',
        album: 'Cruel Summer',
        trackNumber: 5,
      );

      final library = buildLibraryWithPlaylists(
        allSongs: [mercyInPlainFolder, otherCruelSummerTrack],
        existingPlaylists: const [],
      );

      expect(library.folderPlaylists, isEmpty);
      expect(library.albums.length, 1);
      final album = library.albums.values.single;
      expect(album.title, 'Cruel Summer');
      expect(album.artist, 'Various Artists');
      expect(album.songs.length, 2);
    });

    test('playlist tracks are ordered by sorted file path', () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          song(
              path: '/m/[PLAYLIST] Gym/Zebra Song.mp3',
              title: 'Zebra Song'),
          song(
              path: '/m/[PLAYLIST] Gym/Alpha Song.mp3',
              title: 'Alpha Song'),
        ],
        existingPlaylists: const [],
      );

      final playlist = library.folderPlaylists.single;
      expect(playlist.songIds, [
        defaultGenerateSongId('/m/[PLAYLIST] Gym/Alpha Song.mp3'),
        defaultGenerateSongId('/m/[PLAYLIST] Gym/Zebra Song.mp3'),
      ]);
    });

    test('nested [PLAYLIST] folders collapse into the outermost playlist', () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          song(path: '/m/[PLAYLIST] Outer/a.mp3', title: 'A'),
          song(path: '/m/[PLAYLIST] Outer/[PLAYLIST] Inner/b.mp3', title: 'B'),
        ],
        existingPlaylists: const [],
      );

      expect(library.folderPlaylists.length, 1);
      expect(library.folderPlaylists.single.name, 'Outer');
      expect(library.folderPlaylists.single.songIds.length, 2);
    });
  });
}
