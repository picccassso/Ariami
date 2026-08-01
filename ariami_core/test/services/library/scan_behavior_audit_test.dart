import 'package:test/test.dart';

import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/album_builder.dart';
import 'package:ariami_core/services/library/album_grouping.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';
import 'package:ariami_core/services/library/playlist_folder_classifier.dart';

/// Pins the scanner/album/playlist semantics after the Pass-1 playlist
/// correctness fixes (2026-07):
///
/// - [PLAYLIST] folder membership is ADDITIVE: tracks inside playlist
///   folders still join album grouping (or become standalone) normally.
/// - The [PLAYLIST] marker is case-insensitive but must start the name.
/// - Folder playlist entries use deterministic path-sorted order in both
///   the full-scan and incremental rebuild paths.
///
/// ...and after album grouping gained an explicit override plus compilation
/// detection (2026-07-31):
///
/// - `[ALBUM]` folders force one album, overriding tags and the 2-song
///   minimum, and are exempt from every playlist heuristic.
/// - One album title spanning 5+ artists in one place is a compilation, not
///   N same-titled albums — decided BEFORE the per-artist split.
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
    int? discNumber,
    int? duration,
  }) {
    return SongMetadata(
      filePath: path,
      title: title,
      artist: artist,
      albumArtist: albumArtist,
      album: album,
      trackNumber: trackNumber,
      discNumber: discNumber,
      duration: duration,
    );
  }

  /// The YouTube-rip shape: one compilation album tag, but every track
  /// carries its *own* artist as album artist.
  List<SongMetadata> youTubeCompilation({
    required String directory,
    String album = 'Acid Jazz - Verve 50',
    int trackCount = 6,
    int artistOffset = 0,
    int? discNumber,
  }) {
    return [
      for (var i = 0; i < trackCount; i++)
        song(
          path: '$directory/${i + 1} - Track.mp3',
          title: 'Track ${i + 1}',
          artist: 'Artist ${String.fromCharCode(65 + artistOffset + i)}',
          albumArtist: 'Artist ${String.fromCharCode(65 + artistOffset + i)}',
          album: album,
          trackNumber: i + 1,
          discNumber: discNumber,
        ),
    ];
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
    test('unmarked albums come from tags — folder path is not a grouping key',
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

  group('[ALBUM] marker semantics', () {
    test('marker is case-insensitive and must start the folder name', () {
      expect(isAlbumFolderName('[ALBUM] Verve 50'), isTrue);
      expect(isAlbumFolderName('[album] Verve 50'), isTrue);
      expect(isAlbumFolderName('[AlBuM]Verve 50'), isTrue);
      expect(isAlbumFolderName('Verve 50 [ALBUM]'), isFalse);
      expect(isAlbumFolderName(' [ALBUM] Verve 50'), isFalse);
    });

    test('display name strips the marker; a bare marker means "no title"', () {
      expect(albumFolderDisplayName('[ALBUM] Verve 50'), 'Verve 50');
      expect(albumFolderDisplayName('[album]Verve 50'), 'Verve 50');
      expect(albumFolderDisplayName('[ALBUM]'), '');
      expect(albumFolderDisplayName('Verve 50'), 'Verve 50');
    });

    test('detectAlbumFolderPath finds the nearest marked ancestor', () {
      expect(
        detectAlbumFolderPath('/music/[ALBUM] Verve 50/01.mp3'),
        '/music/[ALBUM] Verve 50',
      );
      expect(
        detectAlbumFolderPath('/music/[ALBUM] Verve 50/Disc 1/01.mp3'),
        '/music/[ALBUM] Verve 50',
      );
      // Nested markers: the innermost one wins.
      expect(
        detectAlbumFolderPath('/music/[ALBUM] Box/[ALBUM] Part 2/01.mp3'),
        '/music/[ALBUM] Box/[ALBUM] Part 2',
      );
      expect(detectAlbumFolderPath('/music/Verve 50/01.mp3'), isNull);
    });
  });

  group('[ALBUM] folders override tag grouping', () {
    test('one album per marked folder, however the tags disagree', () {
      final library = AlbumBuilder().buildLibrary(
        youTubeCompilation(directory: '/music/[ALBUM] Verve 50'),
      );

      expect(library.albums.length, 1);
      expect(library.standaloneSongs, isEmpty);
      final album = library.albums.values.single;
      expect(album.songs.length, 6);
      // The folder's own name is the album title.
      expect(album.title, 'Verve 50');
      expect(album.artist, 'Various Artists');
    });

    test('a bare [ALBUM] folder falls back to the tracks\' album tag', () {
      // Only three artists, so pass 2 cannot rescue this — it pins pass 1.
      final library = AlbumBuilder().buildLibrary(
        youTubeCompilation(directory: '/music/[ALBUM]', trackCount: 3),
      );

      expect(library.albums.values.single.title, 'Acid Jazz - Verve 50');
      expect(library.standaloneSongs, isEmpty);
    });

    test('the 2-song minimum does not apply to a marked folder', () {
      final library = AlbumBuilder().buildLibrary([
        song(
          path: '/music/[ALBUM] Single/only.mp3',
          title: 'Only',
          artist: 'A',
          album: 'Whatever The Tag Says',
        ),
      ]);

      expect(library.standaloneSongs, isEmpty);
      expect(library.albums.values.single.title, 'Single');
    });

    test('subfolders of a marked folder join the same album', () {
      // Three artists per disc and repeated track positions across them, so
      // neither disc could qualify as a compilation on its own.
      final library = AlbumBuilder().buildLibrary([
        ...youTubeCompilation(
            directory: '/music/[ALBUM] Verve 50/Disc 1', trackCount: 3),
        ...youTubeCompilation(
            directory: '/music/[ALBUM] Verve 50/Disc 2',
            trackCount: 3,
            artistOffset: 3),
      ]);

      expect(library.albums.length, 1);
      expect(library.albums.values.single.songs.length, 6);
      expect(library.standaloneSongs, isEmpty);
    });

    test('two marked folders sharing a name merge instead of losing songs',
        () {
      final library = AlbumBuilder().buildLibrary([
        for (final source in ['Live Sets', 'Bootlegs'])
          for (var i = 1; i <= 3; i++)
            song(path: '/music/$source/[ALBUM] Live/$i.mp3', title: 'T$i'),
      ]);

      // Same title + artist means one album ID; merging keeps every song.
      expect(library.albums.values.single.songs.length, 6);
      expect(library.standaloneSongs, isEmpty);
    });

    test('a marked subfolder does not un-album its siblings', () {
      final library = AlbumBuilder().buildLibrary([
        ...youTubeCompilation(directory: '/music/Verve'),
        song(
          path: '/music/Verve/[ALBUM] Bonus/1.mp3',
          title: 'Bonus',
          artist: 'Z',
          album: 'Bonus Disc',
        ),
      ]);

      expect(library.albums.length, 2);
      expect(library.standaloneSongs, isEmpty);
      expect(
        library.albums.values.map((a) => a.title).toSet(),
        {'Acid Jazz - Verve 50', 'Bonus'},
      );
    });

    test('marked folders are exempt from playlist folder classification', () {
      final playlistShapedSongs = [
        for (var i = 0; i < 8; i++)
          song(
            path: '/music/[ALBUM] Gym Mix/$i.mp3',
            title: 'Track $i',
            artist: 'Artist $i',
            albumArtist: 'Artist $i',
            album: 'Album $i',
          ),
      ];

      final classification = const PlaylistFolderClassifier().classify(
        songs: playlistShapedSongs,
        libraryRootPath: '/music',
      );

      expect(classification.autoImports, isEmpty);
      expect(classification.suggestions, isEmpty);
    });
  });

  group('compilation detection (before the per-artist split)', () {
    test('one album title over many artists in one folder is one album', () {
      final library = AlbumBuilder().buildLibrary(
        youTubeCompilation(directory: '/music/Acid Jazz - Verve 50'),
      );

      expect(library.albums.length, 1);
      expect(library.standaloneSongs, isEmpty);
      final album = library.albums.values.single;
      expect(album.title, 'Acid Jazz - Verve 50');
      expect(album.artist, 'Various Artists');
      expect(album.isCompilation, isTrue);
      expect(album.songs.length, 6);
    });

    test('a compilation split across disc subfolders still merges', () {
      final library = AlbumBuilder().buildLibrary([
        ...youTubeCompilation(
            directory: '/music/Verve 50/Disc 1', discNumber: 1),
        ...youTubeCompilation(
            directory: '/music/Verve 50/Disc 2',
            artistOffset: 6,
            discNumber: 2),
      ]);

      expect(library.albums.length, 1);
      expect(library.albums.values.single.songs.length, 12);
    });

    test('restarting track numbers in one folder mean separate albums', () {
      // Five same-titled single-artist albums dumped into ONE folder, so
      // folder scoping cannot separate them and the disc/track position
      // check is the only thing standing between them and a bogus merge.
      final library = AlbumBuilder().buildLibrary([
        for (final artist in ['A', 'B', 'C', 'D', 'E'])
          for (var track = 1; track <= 2; track++)
            song(
              path: '/music/Dump/Artist $artist - $track.mp3',
              title: 'Track $track',
              artist: 'Artist $artist',
              albumArtist: 'Artist $artist',
              album: 'Greatest Hits',
              trackNumber: track,
            ),
      ]);

      expect(library.albums.length, 5);
      expect(library.standaloneSongs, isEmpty);
    });

    test('grouping is per folder: a stray file elsewhere carrying the same '
        'album tag does not collapse the compilation', () {
      final library = AlbumBuilder().buildLibrary([
        ...youTubeCompilation(directory: '/music/Verve 50'),
        // A mistagged one-off somewhere else in the library.
        song(
          path: '/music/Other/stray.mp3',
          title: 'Stray',
          artist: 'Someone',
          albumArtist: 'Someone',
          album: 'Acid Jazz - Verve 50',
          trackNumber: 9,
        ),
      ]);

      expect(library.albums.values.single.songs.length, 6);
      expect(library.standaloneSongs.map((s) => s.title), ['Stray']);
    });

    test('real albums sharing a title are never merged, even untagged '
        'track numbers', () {
      // The regression that a title-keyed rule would cause: five properly
      // filed single-artist albums that happen to share a name, with no
      // track numbers to tell them apart.
      final library = AlbumBuilder().buildLibrary([
        for (final artist in ['A', 'B', 'C', 'D', 'E'])
          for (var track = 1; track <= 3; track++)
            song(
              path: '/music/Artist $artist/Greatest Hits/$track.mp3',
              title: 'Track $track',
              artist: 'Artist $artist',
              albumArtist: 'Artist $artist',
              album: 'Greatest Hits',
            ),
      ]);

      expect(library.albums.length, 5);
      expect(
        library.albums.values.map((a) => a.artist).toSet(),
        {'Artist A', 'Artist B', 'Artist C', 'Artist D', 'Artist E'},
      );
    });

    test('fewer than five artists is not enough to merge', () {
      final library = AlbumBuilder().buildLibrary(
        youTubeCompilation(directory: '/music/Split', trackCount: 4),
      );

      expect(library.albums, isEmpty);
      expect(library.standaloneSongs.length, 4);
    });

    test('every input song ends up in exactly one album or standalone', () {
      final songs = [
        ...youTubeCompilation(directory: '/music/Verve 50'),
        ...youTubeCompilation(
            directory: '/music/[ALBUM] Marked', trackCount: 3),
        for (final artist in ['A', 'B'])
          for (var track = 1; track <= 2; track++)
            song(
              path: '/music/Artist $artist/LP/$track.mp3',
              title: 'T$track',
              artist: 'Artist $artist',
              albumArtist: 'Artist $artist',
              album: 'LP',
              trackNumber: track,
            ),
        song(path: '/music/loose.mp3', title: 'Loose'),
      ];

      final library = AlbumBuilder().buildLibrary(songs);

      final placed = <String>[
        for (final album in library.albums.values)
          for (final s in album.songs) s.filePath,
        ...library.standaloneSongs.map((s) => s.filePath),
      ];
      expect(placed.length, songs.length);
      expect(placed.toSet(), songs.map((s) => s.filePath).toSet());
    });

    test('a single-artist album with many features is never a compilation',
        () {
      final library = AlbumBuilder().buildLibrary([
        for (var track = 1; track <= 6; track++)
          song(
            path: '/music/Eminem/Recovery/$track.mp3',
            title: 'Track $track',
            artist: 'Eminem feat. Guest $track',
            albumArtist: 'Eminem',
            album: 'Recovery',
            trackNumber: track,
          ),
      ]);

      final album = library.albums.values.single;
      expect(album.artist, 'Eminem');
      expect(album.isCompilation, isFalse);
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

    test(
        'an [ALBUM] folder inside a playlist folder keeps its album AND its '
        'playlist membership', () {
      // Without the marker these tracks would trip the downloader-artifact
      // guard (one album tag, 3+ grouping artists inside a playlist folder)
      // and be forced standalone.
      final tracks = youTubeCompilation(
        directory: '/music/[PLAYLIST] Gym/[ALBUM] Verve 50',
      );

      final library = buildLibraryWithPlaylists(
        allSongs: tracks,
        existingPlaylists: const [],
      );

      expect(library.standaloneSongs, isEmpty);
      expect(library.albums.values.single.title, 'Verve 50');
      expect(library.folderPlaylists.single.name, 'Gym');
      expect(library.folderPlaylists.single.songIds.length, tracks.length);
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
