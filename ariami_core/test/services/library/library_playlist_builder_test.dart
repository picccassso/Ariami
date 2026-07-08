import 'package:test/test.dart';

import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';

SongMetadata _song({
  required String path,
  String? title,
  String? artist,
  String? albumArtist,
  String? album,
}) {
  return SongMetadata(
    filePath: path,
    title: title,
    artist: artist,
    albumArtist: albumArtist,
    album: album,
  );
}

void main() {
  group('case-insensitive [PLAYLIST] markers', () {
    test('[playlist], [Playlist] and [PLAYLIST] folders all create playlists',
        () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          _song(path: '/m/[PLAYLIST] Gym/a.mp3', title: 'A'),
          _song(path: '/m/[playlist] Chill/b.mp3', title: 'B'),
          _song(path: '/m/[Playlist] Focus/c.mp3', title: 'C'),
        ],
        existingPlaylists: const [],
      );

      expect(library.folderPlaylists, hasLength(3));
      expect(
        library.folderPlaylists.map((p) => p.name),
        containsAll(['Gym', 'Chill', 'Focus']),
      );
    });

    test('marker is stripped from the displayed name regardless of case', () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          _song(path: '/m/[playlist] Summer Vibes/a.mp3', title: 'A'),
        ],
        existingPlaylists: const [],
      );

      expect(library.folderPlaylists.single.name, 'Summer Vibes');
    });
  });

  group('additive playlist membership', () {
    test('playlist-folder track with album tags is in both album and playlist',
        () {
      const playlistTrackPath = '/m/[PLAYLIST] Gym/mercy.mp3';
      final library = buildLibraryWithPlaylists(
        allSongs: [
          _song(
            path: playlistTrackPath,
            title: 'Mercy',
            artist: 'Kanye West',
            albumArtist: 'Various Artists',
            album: 'Cruel Summer',
          ),
          _song(
            path: '/m/Cruel Summer/to-the-world.mp3',
            title: 'To The World',
            artist: 'Kanye West',
            albumArtist: 'Various Artists',
            album: 'Cruel Summer',
          ),
        ],
        existingPlaylists: const [],
      );

      expect(library.albums, hasLength(1));
      expect(
        library.albums.values.single.songs.map((s) => s.filePath),
        contains(playlistTrackPath),
      );
      expect(library.folderPlaylists.single.songIds,
          contains(defaultGenerateSongId(playlistTrackPath)));
      expect(
        library.standaloneSongs.map((s) => s.filePath),
        isNot(contains(playlistTrackPath)),
      );
    });

    test('playlist-folder track without album tags stays standalone', () {
      const playlistTrackPath = '/m/[PLAYLIST] Gym/loose-track.mp3';
      final library = buildLibraryWithPlaylists(
        allSongs: [
          _song(path: playlistTrackPath, title: 'Loose Track'),
        ],
        existingPlaylists: const [],
      );

      expect(library.albums, isEmpty);
      expect(library.standaloneSongs.single.filePath, playlistTrackPath);
      expect(library.folderPlaylists.single.songIds,
          [defaultGenerateSongId(playlistTrackPath)]);
    });

    test('normal album folders still group as albums, no playlist created',
        () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          _song(
              path: '/m/Album/1.mp3', title: 'One', artist: 'A', album: 'X'),
          _song(
              path: '/m/Album/2.mp3', title: 'Two', artist: 'A', album: 'X'),
        ],
        existingPlaylists: const [],
      );

      expect(library.albums, hasLength(1));
      expect(library.folderPlaylists, isEmpty);
    });

    test('normal mixed folders do not become playlists', () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          _song(path: '/m/Random Mix/1.mp3', title: 'One', artist: 'A'),
          _song(path: '/m/Random Mix/2.mp3', title: 'Two', artist: 'B'),
        ],
        existingPlaylists: const [],
      );

      expect(library.folderPlaylists, isEmpty);
      expect(library.standaloneSongs, hasLength(2));
    });
  });

  group('deterministic playlist ordering', () {
    test('numbered files use natural order past track 99', () {
      final songs = [
        _song(path: '/m/[PLAYLIST] Big/118 - A.mp3', title: 'A'),
        _song(path: '/m/[PLAYLIST] Big/12 - B.mp3', title: 'B'),
        _song(path: '/m/[PLAYLIST] Big/120 - C.mp3', title: 'C'),
        _song(path: '/m/[PLAYLIST] Big/02 - D.mp3', title: 'D'),
      ];

      final library = buildLibraryWithPlaylists(
        allSongs: songs,
        existingPlaylists: const [],
      );

      expect(library.folderPlaylists.single.songIds, [
        defaultGenerateSongId('/m/[PLAYLIST] Big/02 - D.mp3'),
        defaultGenerateSongId('/m/[PLAYLIST] Big/12 - B.mp3'),
        defaultGenerateSongId('/m/[PLAYLIST] Big/118 - A.mp3'),
        defaultGenerateSongId('/m/[PLAYLIST] Big/120 - C.mp3'),
      ]);
    });

    test('entry order is path-sorted regardless of input song order', () {
      final songs = [
        _song(path: '/m/[PLAYLIST] Gym/zebra.mp3', title: 'Zebra'),
        _song(path: '/m/[PLAYLIST] Gym/alpha.mp3', title: 'Alpha'),
        _song(path: '/m/[PLAYLIST] Gym/mid.mp3', title: 'Mid'),
      ];
      final expectedIds = [
        defaultGenerateSongId('/m/[PLAYLIST] Gym/alpha.mp3'),
        defaultGenerateSongId('/m/[PLAYLIST] Gym/mid.mp3'),
        defaultGenerateSongId('/m/[PLAYLIST] Gym/zebra.mp3'),
      ];

      final forward = buildLibraryWithPlaylists(
        allSongs: songs,
        existingPlaylists: const [],
      );
      final reversed = buildLibraryWithPlaylists(
        allSongs: songs.reversed.toList(),
        existingPlaylists: const [],
      );

      expect(forward.folderPlaylists.single.songIds, expectedIds);
      expect(reversed.folderPlaylists.single.songIds, expectedIds);
    });

    test('playlist list itself is sorted by folder path', () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          _song(path: '/m/[PLAYLIST] Zulu/a.mp3', title: 'A'),
          _song(path: '/m/[PLAYLIST] Alpha/b.mp3', title: 'B'),
        ],
        existingPlaylists: const [],
      );

      expect(
        library.folderPlaylists.map((p) => p.name).toList(),
        ['Alpha', 'Zulu'],
      );
    });
  });

  group('duplicate-aware playlist membership', () {
    test('a deduped playlist copy keeps an entry pointing at the canonical ID',
        () {
      const canonicalPath = '/m/Album/song.mp3';
      const dedupedCopyPath = '/m/[PLAYLIST] Gym/song-copy.mp3';

      final library = buildLibraryWithPlaylists(
        allSongs: [
          // Only the canonical copy survives dedup and reaches the builder.
          _song(
              path: canonicalPath, title: 'Song', artist: 'A', album: 'X'),
          _song(
              path: '/m/Album/other.mp3',
              title: 'Other',
              artist: 'A',
              album: 'X'),
        ],
        existingPlaylists: const [],
        duplicateToOriginalPath: const {dedupedCopyPath: canonicalPath},
      );

      expect(library.folderPlaylists, hasLength(1),
          reason: 'the playlist folder is discovered from the deduped copy');
      expect(
        library.folderPlaylists.single.songIds,
        [defaultGenerateSongId(canonicalPath)],
      );
      expect(library.duplicateToOriginalPath,
          {dedupedCopyPath: canonicalPath});
    });
  });

  group('playlist-name-as-album guard', () {
    test(
        'tracks whose album tag repeats the playlist name stay standalone '
        '(no fake per-artist albums)', () {
      // The "Christmas Hits" pattern: a downloader wrote the playlist name
      // into every track's album field, each with its own album artist.
      final songs = [
        for (var i = 1; i <= 4; i++) ...[
          _song(
            path: '/m/[PLAYLIST] Christmas Hits/0$i-a.mp3',
            title: 'Song ${i}a',
            artist: 'Artist $i',
            albumArtist: 'Artist $i',
            album: 'Christmas Hits',
          ),
          _song(
            path: '/m/[PLAYLIST] Christmas Hits/0$i-b.mp3',
            title: 'Song ${i}b',
            artist: 'Artist $i',
            albumArtist: 'Artist $i',
            album: 'christmas hits', // case-insensitive match
          ),
        ],
      ];

      final library = buildLibraryWithPlaylists(
        allSongs: songs,
        existingPlaylists: const [],
      );

      expect(library.albums, isEmpty,
          reason: 'the playlist-name album tag must not shatter into fake '
              'per-artist albums');
      expect(library.standaloneSongs, hasLength(8));
      expect(library.folderPlaylists.single.songIds, hasLength(8),
          reason: 'all tracks still belong to the playlist');
    });

    test(
        'a shared album tag spanning many album artists is caught even when '
        'the folder was renamed (tag != folder name)', () {
      // The "AIENP's sleep time" pattern: folder is "[PLAYLIST] Sleep Time"
      // but every track's album tag holds the original playlist name, each
      // with its own album artist.
      final songs = [
        for (final artist in ['Russ', 'Usher', 'mgk', 'G-Eazy']) ...[
          _song(
            path: '/m/[PLAYLIST] Sleep Time/$artist-1.mp3',
            title: '$artist One',
            artist: artist,
            albumArtist: artist,
            album: "AIENP's sleep time",
          ),
          _song(
            path: '/m/[PLAYLIST] Sleep Time/$artist-2.mp3',
            title: '$artist Two',
            artist: artist,
            albumArtist: artist,
            album: "AIENP's sleep time",
          ),
        ],
      ];

      final library = buildLibraryWithPlaylists(
        allSongs: songs,
        existingPlaylists: const [],
      );

      expect(library.albums, isEmpty,
          reason: 'one album tag across 4 album artists in a playlist '
              'folder is a downloader artifact, not 4 real albums');
      expect(library.standaloneSongs, hasLength(8));
      expect(library.folderPlaylists.single.songIds, hasLength(8));
    });

    test(
        'a single-artist playlist with a prefixed album tag is caught via '
        'normalized containment', () {
      // "[PLAYLIST] NF Sad Songs" full of album="AIENP's NF Sad Songs":
      // one album artist, tag != folder name — only containment catches it.
      final library = buildLibraryWithPlaylists(
        allSongs: [
          for (var i = 1; i <= 4; i++)
            _song(
              path: '/m/[PLAYLIST] NF Sad Songs/0$i.mp3',
              title: 'Song $i',
              artist: 'NF',
              albumArtist: 'NF',
              album: "AIENP's NF Sad Songs",
            ),
        ],
        existingPlaylists: const [],
      );

      expect(library.albums, isEmpty);
      expect(library.standaloneSongs, hasLength(4));
      expect(library.folderPlaylists.single.songIds, hasLength(4));
    });

    test(
        'short playlist names never swallow real albums via containment',
        () {
      // "[PLAYLIST] Elvis" (5 normalized chars, below the 8-char minimum)
      // containing the genuine album "Elvis' Golden Records".
      final library = buildLibraryWithPlaylists(
        allSongs: [
          for (var i = 1; i <= 3; i++)
            _song(
              path: '/m/[PLAYLIST] Elvis/0$i.mp3',
              title: 'Song $i',
              artist: 'Elvis Presley',
              albumArtist: 'Elvis Presley',
              album: "Elvis' Golden Records",
            ),
        ],
        existingPlaylists: const [],
      );

      expect(library.albums, hasLength(1),
          reason: 'a real album must survive a short playlist name');
      expect(library.albums.values.single.songs, hasLength(3));
    });

    test(
        'a Various Artists compilation inside a playlist folder still forms '
        'one album', () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          for (var i = 1; i <= 4; i++)
            _song(
              path: '/m/[PLAYLIST] Gym/now-$i.mp3',
              title: 'Hit $i',
              artist: 'Pop Artist $i',
              albumArtist: 'Various Artists',
              album: 'NOW 100',
            ),
        ],
        existingPlaylists: const [],
      );

      expect(library.albums, hasLength(1),
          reason: 'a single "Various Artists" grouping artist is a real '
              'compilation, not an artifact');
      expect(library.albums.values.single.songs, hasLength(4));
    });

    test('an album tag shared by only two artists is left alone', () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          for (final artist in ['Artist A', 'Artist B'])
            for (var i = 1; i <= 2; i++)
              _song(
                path: '/m/[PLAYLIST] Mix/$artist-$i.mp3',
                title: '$artist $i',
                artist: artist,
                albumArtist: artist,
                album: 'Split EP',
              ),
        ],
        existingPlaylists: const [],
      );

      expect(library.albums, hasLength(2),
          reason: 'below the 3-artist threshold the tags are trusted');
    });

    test('genuine album tags inside playlist folders still group', () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          _song(
            path: '/m/[PLAYLIST] Gym/mercy.mp3',
            title: 'Mercy',
            artist: 'Kanye West',
            albumArtist: 'Various Artists',
            album: 'Cruel Summer',
          ),
          _song(
            path: '/m/Cruel Summer/to-the-world.mp3',
            title: 'To The World',
            artist: 'Kanye West',
            albumArtist: 'Various Artists',
            album: 'Cruel Summer',
          ),
        ],
        existingPlaylists: const [],
      );

      expect(library.albums, hasLength(1),
          reason: '"Cruel Summer" is not the playlist name, so it groups');
      expect(library.albums.values.single.songs, hasLength(2));
    });

    test('an identically named album in a NORMAL folder is unaffected', () {
      final library = buildLibraryWithPlaylists(
        allSongs: [
          _song(
            path: '/m/Christmas Hits/1.mp3',
            title: 'One',
            artist: 'A',
            album: 'Christmas Hits',
          ),
          _song(
            path: '/m/Christmas Hits/2.mp3',
            title: 'Two',
            artist: 'A',
            album: 'Christmas Hits',
          ),
        ],
        existingPlaylists: const [],
      );

      expect(library.albums, hasLength(1),
          reason: 'the guard only applies inside playlist folders');
    });
  });

  group('m3u playlists on incremental rebuild', () {
    test('are carried through with their explicit (non-sorted) order', () {
      const trackA = '/m/Album/a.mp3';
      const trackB = '/m/Album/b.mp3';
      final m3uPlaylist = FolderPlaylist(
        id: FolderPlaylist.generateId('/m/mix.m3u'),
        name: 'mix',
        folderPath: '/m/mix.m3u',
        // Deliberately reverse of path order.
        songIds: [defaultGenerateSongId(trackB), defaultGenerateSongId(trackA)],
      );

      final library = buildLibraryWithPlaylists(
        allSongs: [
          _song(path: trackA, title: 'A', artist: 'X', album: 'Album'),
          _song(path: trackB, title: 'B', artist: 'X', album: 'Album'),
        ],
        existingPlaylists: [m3uPlaylist],
      );

      expect(library.folderPlaylists, hasLength(1));
      expect(
        library.folderPlaylists.single.songIds,
        [defaultGenerateSongId(trackB), defaultGenerateSongId(trackA)],
        reason: 'm3u playlists keep their explicit order, unlike folder '
            'playlists which are path-sorted',
      );
    });

    test('drop entries whose songs left the library, vanish when empty', () {
      const survivor = '/m/Album/a.mp3';
      const removed = '/m/Album/gone.mp3';
      final m3uPlaylist = FolderPlaylist(
        id: FolderPlaylist.generateId('/m/mix.m3u8'),
        name: 'mix',
        folderPath: '/m/mix.m3u8',
        songIds: [
          defaultGenerateSongId(removed),
          defaultGenerateSongId(survivor),
        ],
      );

      final library = buildLibraryWithPlaylists(
        allSongs: [_song(path: survivor, title: 'A')],
        existingPlaylists: [m3uPlaylist],
      );
      expect(library.folderPlaylists.single.songIds,
          [defaultGenerateSongId(survivor)]);

      final emptied = buildLibraryWithPlaylists(
        allSongs: const [],
        existingPlaylists: [m3uPlaylist],
      );
      expect(emptied.folderPlaylists, isEmpty);
    });
  });

  group('buildPlaylistFolderMap', () {
    test('includes duplicate file paths in playlist folder membership', () {
      final map = buildPlaylistFolderMap(
        songs: [
          _song(path: '/m/[PLAYLIST] Gym/live.mp3', title: 'Live'),
        ],
        existingPlaylists: const [],
        duplicateFilePaths: const ['/m/[PLAYLIST] Gym/deduped.mp3'],
      );

      expect(
        map['/m/[PLAYLIST] Gym'],
        containsAll([
          '/m/[PLAYLIST] Gym/live.mp3',
          '/m/[PLAYLIST] Gym/deduped.mp3',
        ]),
      );
    });

    test('keeps known playlist folders alive when only deduped copies remain',
        () {
      final existing = FolderPlaylist(
        id: FolderPlaylist.generateId('/m/[PLAYLIST] Gym'),
        name: 'Gym',
        folderPath: '/m/[PLAYLIST] Gym',
        songIds: const [],
      );

      final map = buildPlaylistFolderMap(
        songs: const [],
        existingPlaylists: [existing],
        duplicateFilePaths: const ['/m/[PLAYLIST] Gym/deduped.mp3'],
      );

      expect(map['/m/[PLAYLIST] Gym'], ['/m/[PLAYLIST] Gym/deduped.mp3']);
    });
  });
}
