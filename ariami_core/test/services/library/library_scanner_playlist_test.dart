import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:test/test.dart';

import 'package:ariami_core/models/file_change.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/change_processor.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';
import 'package:ariami_core/services/library/library_scanner_isolate.dart';

/// Full-scan behaviour of [PLAYLIST] folders against real files on disk,
/// plus parity with the incremental (watcher) rebuild path.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ariami_playlist_scan_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Builds a minimal ID3v1 tag (128-byte "TAG" trailer).
  List<int> id3v1Tag({
    required String title,
    required String artist,
    required String album,
  }) {
    List<int> fixedField(String value, int length) {
      final bytes = ascii.encode(value);
      return [
        ...bytes.take(length),
        ...List<int>.filled(length - min(bytes.length, length), 0),
      ];
    }

    return [
      ...ascii.encode('TAG'),
      ...fixedField(title, 30),
      ...fixedField(artist, 30),
      ...fixedField(album, 30),
      ...ascii.encode('2024'),
      ...List<int>.filled(30, 0), // comment
      255, // genre: none
    ];
  }

  Future<String> writeAudio(
    String relativePath,
    List<int> body, {
    String? title,
    String? artist,
    String? album,
  }) async {
    final file = File('${tempDir.path}/$relativePath');
    await file.parent.create(recursive: true);
    final bytes = <int>[
      ...body,
      if (title != null && artist != null && album != null)
        ...id3v1Tag(title: title, artist: artist, album: album),
    ];
    await file.writeAsBytes(bytes);
    return file.path;
  }

  test(
      'a tagged track inside a [playlist] folder joins its album and the '
      'playlist (marker case-insensitive, name stripped)', () async {
    await writeAudio(
      'Album/one.mp3',
      List<int>.filled(4096, 1),
      title: 'One',
      artist: 'Ye',
      album: 'Cruel Summer',
    );
    final playlistTrackPath = await writeAudio(
      '[playlist] Gym/two.mp3',
      List<int>.filled(4096, 2),
      title: 'Two',
      artist: 'Ye',
      album: 'Cruel Summer',
    );

    final result = await LibraryScannerIsolate.scan(tempDir.path);
    final library = result.library!;

    expect(library.albums, hasLength(1),
        reason: 'playlist membership must not block album grouping');
    final album = library.albums.values.single;
    expect(album.title, 'Cruel Summer');
    expect(album.songs.map((s) => s.filePath), contains(playlistTrackPath));

    expect(library.folderPlaylists, hasLength(1));
    expect(library.folderPlaylists.single.name, 'Gym');
    expect(library.folderPlaylists.single.songIds,
        [defaultGenerateSongId(playlistTrackPath)]);

    expect(
      library.standaloneSongs.map((s) => s.filePath),
      isNot(contains(playlistTrackPath)),
      reason: 'playlist tracks must no longer be forced standalone',
    );
  });

  test(
      'full scan orders playlist entries by sorted path and an incremental '
      'rebuild preserves that order', () async {
    final zebra =
        await writeAudio('[PLAYLIST] Mix/zebra.mp3', List<int>.filled(4096, 3));
    final alpha =
        await writeAudio('[PLAYLIST] Mix/alpha.mp3', List<int>.filled(4096, 4));
    final kilo =
        await writeAudio('[PLAYLIST] Mix/kilo.mp3', List<int>.filled(4096, 5));

    final result = await LibraryScannerIsolate.scan(tempDir.path);
    final scannedLibrary = result.library!;

    final expectedOrder = [
      defaultGenerateSongId(alpha),
      defaultGenerateSongId(kilo),
      defaultGenerateSongId(zebra),
    ];
    expect(scannedLibrary.folderPlaylists.single.songIds, expectedOrder,
        reason: 'full scan must use canonical path-sorted order');

    // Simulate a watcher batch adding an unrelated song.
    final newSongPath = '${tempDir.path}/loose/new.mp3';
    final update = LibraryUpdate(
      addedSongIds: {defaultGenerateSongId(newSongPath)},
      removedSongIds: {},
      modifiedSongIds: {},
      affectedAlbumIds: {},
      timestamp: DateTime.now(),
      extractedMetadata: {
        newSongPath: SongMetadata(filePath: newSongPath, title: 'New'),
      },
    );
    final rebuilt = await ChangeProcessor().applyUpdates(
      update,
      scannedLibrary,
      sourceChanges: [
        FileChange(
          path: newSongPath,
          type: FileChangeType.added,
          timestamp: DateTime.now(),
        ),
      ],
    );

    expect(rebuilt.folderPlaylists.single.songIds, expectedOrder,
        reason: 'incremental rebuild must not silently reorder playlists');
  });

  test(
      'a playlist copy deduped to an album original keeps its entry across '
      'full scan and incremental rebuild', () async {
    final identicalBytes = List<int>.filled(4096, 6);
    final canonicalPath = await writeAudio(
      'Album/one.mp3',
      identicalBytes,
      title: 'One',
      artist: 'A',
      album: 'X',
    );
    await writeAudio(
      'Album/other.mp3',
      List<int>.filled(4096, 7),
      title: 'Other',
      artist: 'A',
      album: 'X',
    );
    // Byte-identical copy inside the playlist folder -> filtered as duplicate.
    await writeAudio(
      '[PLAYLIST] Gym/one-copy.mp3',
      identicalBytes,
      title: 'One',
      artist: 'A',
      album: 'X',
    );

    final result = await LibraryScannerIsolate.scan(tempDir.path);
    final scannedLibrary = result.library!;

    expect(scannedLibrary.albums, hasLength(1));
    expect(scannedLibrary.albums.values.single.songs, hasLength(2));
    expect(
      scannedLibrary.folderPlaylists.single.songIds,
      [defaultGenerateSongId(canonicalPath)],
      reason: 'full scan remaps the deduped copy to the canonical song ID',
    );
    expect(scannedLibrary.duplicateToOriginalPath.values,
        contains(canonicalPath));

    // Unrelated watcher change; the deduped entry must survive the rebuild.
    final newSongPath = '${tempDir.path}/loose/new.mp3';
    final update = LibraryUpdate(
      addedSongIds: {defaultGenerateSongId(newSongPath)},
      removedSongIds: {},
      modifiedSongIds: {},
      affectedAlbumIds: {},
      timestamp: DateTime.now(),
      extractedMetadata: {
        newSongPath: SongMetadata(filePath: newSongPath, title: 'New'),
      },
    );
    final rebuilt = await ChangeProcessor().applyUpdates(
      update,
      scannedLibrary,
      sourceChanges: [
        FileChange(
          path: newSongPath,
          type: FileChangeType.added,
          timestamp: DateTime.now(),
        ),
      ],
    );

    expect(
      rebuilt.folderPlaylists.single.songIds,
      [defaultGenerateSongId(canonicalPath)],
      reason: 'incremental rebuild must match full-scan dedupe behaviour',
    );
  });

  test('full scan uses natural order for numbered playlist files', () async {
    // 2-digit padding plus 100+ tracks: plain sort would put 12 after 118.
    final paths = <String>[];
    for (final n in ['02', '12', '100', '118', '120']) {
      paths.add(await writeAudio(
          '[PLAYLIST] Big/$n - Track.mp3', List<int>.filled(2048, 40 + paths.length)));
    }

    final result = await LibraryScannerIsolate.scan(tempDir.path);
    final playlist = result.library!.folderPlaylists.single;

    expect(playlist.songIds, [for (final p in paths) defaultGenerateSongId(p)],
        reason: 'numeric-aware order: 02, 12, 100, 118, 120');
  });

  test(
      'album tags that repeat the playlist name do not create fake albums '
      'on a full scan', () async {
    // Mirrors the real-world "Christmas Hits Private" pattern: playlist name
    // written into every album tag, per-track album artists, no track tags.
    for (var i = 1; i <= 3; i++) {
      await writeAudio(
        '[PLAYLIST] Xmas/0$i - Song A$i.mp3',
        List<int>.filled(2048, 50 + i),
        title: 'Song A$i',
        artist: 'Artist $i',
        album: 'Xmas',
      );
      await writeAudio(
        '[PLAYLIST] Xmas/1$i - Song B$i.mp3',
        List<int>.filled(2048, 60 + i),
        title: 'Song B$i',
        artist: 'Artist $i',
        album: 'Xmas',
      );
    }

    final result = await LibraryScannerIsolate.scan(tempDir.path);
    final library = result.library!;

    expect(library.albums, isEmpty,
        reason: 'no fake per-artist "Xmas" albums');
    expect(library.standaloneSongs, hasLength(6));
    expect(library.folderPlaylists.single.name, 'Xmas');
    expect(library.folderPlaylists.single.songIds, hasLength(6));
  });

  group('M3U/M3U8 playlists', () {
    test(
        'imports an m3u with relative/absolute/missing/duplicate entries, '
        'preserving file order', () async {
      final one = await writeAudio('Album/one.mp3', List<int>.filled(4096, 10),
          title: 'One', artist: 'A', album: 'X');
      final two = await writeAudio('Album/two.mp3', List<int>.filled(4096, 11),
          title: 'Two', artist: 'A', album: 'X');

      final m3uFile = File('${tempDir.path}/lists/mix.m3u');
      await m3uFile.parent.create(recursive: true);
      await m3uFile.writeAsString('''
#EXTM3U
#EXTINF:1,A - Two
../Album/two.mp3
$one
../Album/missing.mp3
../Album/two.mp3
''');

      final result = await LibraryScannerIsolate.scan(tempDir.path);
      final library = result.library!;

      final m3uPlaylist = library.folderPlaylists
          .singleWhere((p) => p.folderPath == m3uFile.path);
      expect(m3uPlaylist.name, 'mix');
      expect(
        m3uPlaylist.songIds,
        [defaultGenerateSongId(two), defaultGenerateSongId(one)],
        reason: 'm3u order is preserved (not path-sorted) and the repeated '
            'entry is deduplicated',
      );

      expect(
        result.scanDiagnostics.failedFiles
            .any((f) => f.path.endsWith('missing.mp3')),
        isTrue,
        reason: 'missing m3u entries surface as scan diagnostics',
      );

      // The album itself is untouched by the m3u.
      expect(library.albums.values.single.songs, hasLength(2));
    });

    test('an m3u entry pointing at a deduped copy resolves to the canonical '
        'song', () async {
      final identicalBytes = List<int>.filled(4096, 12);
      final canonical = await writeAudio(
          'Album/one.mp3', identicalBytes,
          title: 'One', artist: 'A', album: 'X');
      await writeAudio('Album/other.mp3', List<int>.filled(4096, 13),
          title: 'Other', artist: 'A', album: 'X');
      final copy = await writeAudio('Copies/one-copy.mp3', identicalBytes,
          title: 'One', artist: 'A', album: 'X');

      final m3uFile = File('${tempDir.path}/mix.m3u8');
      await m3uFile.writeAsString('$copy\n');

      final result = await LibraryScannerIsolate.scan(tempDir.path);
      final m3uPlaylist = result.library!.folderPlaylists
          .singleWhere((p) => p.folderPath == m3uFile.path);

      expect(m3uPlaylist.songIds, [defaultGenerateSongId(canonical)]);
    });

    test('a garbage m3u never breaks the scan', () async {
      await writeAudio('Album/one.mp3', List<int>.filled(4096, 14),
          title: 'One', artist: 'A', album: 'X');
      await writeAudio('Album/two.mp3', List<int>.filled(4096, 15),
          title: 'Two', artist: 'A', album: 'X');
      await File('${tempDir.path}/broken.m3u')
          .writeAsBytes(List<int>.generate(512, (i) => (i * 37) % 256));

      final result = await LibraryScannerIsolate.scan(tempDir.path);

      expect(result.library, isNotNull);
      expect(result.library!.albums, hasLength(1));
      expect(
        result.library!.folderPlaylists
            .where((p) => p.folderPath.endsWith('broken.m3u')),
        isEmpty,
        reason: 'garbage entries match no songs, so no playlist is created',
      );
    });

    test('m3u playlists survive incremental rebuilds and drop removed songs',
        () async {
      final one = await writeAudio('Album/one.mp3', List<int>.filled(4096, 16),
          title: 'One', artist: 'A', album: 'X');
      final two = await writeAudio('Album/two.mp3', List<int>.filled(4096, 17),
          title: 'Two', artist: 'A', album: 'X');
      await File('${tempDir.path}/mix.m3u')
          .writeAsString('Album/two.mp3\nAlbum/one.mp3\n');

      final scanned = (await LibraryScannerIsolate.scan(tempDir.path)).library!;
      final playlistBefore = scanned.folderPlaylists
          .singleWhere((p) => p.folderPath.endsWith('mix.m3u'));
      expect(playlistBefore.songIds,
          [defaultGenerateSongId(two), defaultGenerateSongId(one)]);

      // Watcher removes one.mp3.
      final update = LibraryUpdate(
        addedSongIds: {},
        removedSongIds: {defaultGenerateSongId(one)},
        modifiedSongIds: {},
        affectedAlbumIds: {},
        timestamp: DateTime.now(),
      );
      final rebuilt = await ChangeProcessor().applyUpdates(
        update,
        scanned,
        sourceChanges: [
          FileChange(
            path: one,
            type: FileChangeType.removed,
            timestamp: DateTime.now(),
          ),
        ],
      );

      final playlistAfter = rebuilt.folderPlaylists
          .singleWhere((p) => p.folderPath.endsWith('mix.m3u'));
      expect(playlistAfter.songIds, [defaultGenerateSongId(two)],
          reason: 'the m3u playlist survives the rebuild minus the removed '
              'song, keeping its explicit order');
      expect(playlistAfter.id, playlistBefore.id);
    });
  });

  group('playlist suggestions (scan diagnostics)', () {
    test(
        'a mixed folder is suggested, while explicit [PLAYLIST] folders and '
        'album folders are not', () async {
      // Album-shaped folder.
      await writeAudio('Album/one.mp3', List<int>.filled(4096, 20),
          title: 'One', artist: 'A', album: 'X');
      await writeAudio('Album/two.mp3', List<int>.filled(4096, 21),
          title: 'Two', artist: 'A', album: 'X');
      // Explicit playlist folder.
      await writeAudio('[PLAYLIST] Gym/a.mp3', List<int>.filled(4096, 22),
          title: 'GymSong', artist: 'B', album: 'Y');
      // Mixed dump: many artists, many albums, no numbering.
      for (var i = 0; i < 6; i++) {
        await writeAudio(
          'Old iPod Dump/song$i.mp3',
          List<int>.filled(4096, 30 + i),
          title: 'Song $i',
          artist: 'Artist $i',
          album: 'Album $i',
        );
      }

      final result = await LibraryScannerIsolate.scan(tempDir.path);
      final suggestions = result.scanDiagnostics.playlistSuggestions;

      expect(suggestions, hasLength(1),
          reason: 'only the mixed dump should be suggested');
      final suggestion = suggestions.single;
      expect(suggestion.name, 'Old iPod Dump');
      expect(suggestion.songCount, 6);
      expect(suggestion.missingTags, isFalse);

      // Suggestions are advisory: no playlist was actually created for it.
      expect(
        result.library!.folderPlaylists.map((p) => p.name).toList(),
        ['Gym'],
      );
    });
  });
}
