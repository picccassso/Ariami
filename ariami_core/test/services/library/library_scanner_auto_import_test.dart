import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:test/test.dart';

import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';
import 'package:ariami_core/services/library/library_scanner_isolate.dart';

/// Fresh-install behaviour of high-confidence playlist detection: a normal
/// folder full of mixed songs must become a playlist without the user
/// knowing about `[PLAYLIST]` markers, while album-shaped folders are never
/// touched and medium-confidence folders remain advisory suggestions.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ariami_auto_import_');
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

  var fillByte = 1;
  Future<String> writeAudio(
    String relativePath, {
    String? title,
    String? artist,
    String? album,
  }) async {
    final file = File('${tempDir.path}/$relativePath');
    await file.parent.create(recursive: true);
    final bytes = <int>[
      ...List<int>.filled(4096, fillByte++),
      if (title != null && artist != null && album != null)
        ...id3v1Tag(title: title, artist: artist, album: album),
    ];
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// A high-confidence playlist shape: [count] loose tracks, each from its
  /// own artist and album.
  Future<List<String>> writeMixedFolder(String folderName, int count) async {
    final paths = <String>[];
    for (var i = 1; i <= count; i++) {
      paths.add(await writeAudio(
        '$folderName/song $i.mp3',
        title: 'Song $i',
        artist: '$folderName Artist $i',
        album: '$folderName Album $i',
      ));
    }
    return paths;
  }

  group('fresh install (no markers, no decisions)', () {
    test(
        'a high-confidence mixed folder auto-imports as a playlist with '
        'additive album membership and a marker-folder-style identity',
        () async {
      final gymPath = '${tempDir.path}/Gym';
      final gymSongs = await writeMixedFolder('Gym', 8);
      // One Gym track shares its album with a track outside the folder, to
      // prove membership stays additive.
      final shared = await writeAudio(
        'Gym/zebra.mp3',
        title: 'Zebra',
        artist: 'Ye',
        album: 'Cruel Summer',
      );
      final outside = await writeAudio(
        'Albums/one.mp3',
        title: 'One',
        artist: 'Ye',
        album: 'Cruel Summer',
      );

      final result = await LibraryScannerIsolate.scan(tempDir.path);
      final library = result.library!;

      final playlist = library.folderPlaylists.single;
      expect(playlist.name, 'Gym');
      expect(playlist.id, FolderPlaylist.generateId(gymPath),
          reason: 'same ID scheme as marker folders, stable across scans');
      expect(playlist.songIds, hasLength(9),
          reason: 'all 9 files directly in Gym belong to the playlist');
      expect(playlist.songIds, contains(defaultGenerateSongId(shared)));
      for (final path in gymSongs) {
        expect(playlist.songIds, contains(defaultGenerateSongId(path)));
      }

      // Additive: the shared-album track still groups with the outside one.
      final cruelSummer = library.albums.values
          .singleWhere((album) => album.title == 'Cruel Summer');
      expect(
        cruelSummer.songs.map((s) => s.filePath),
        containsAll([shared, outside]),
      );

      // Diagnostics report the import; nothing is left as a suggestion.
      expect(
        result.scanDiagnostics.autoImportedPlaylistFolders
            .map((s) => s.folderPath),
        [gymPath],
      );
      expect(result.scanDiagnostics.playlistSuggestions, isEmpty);
    });

    test(
        'a medium-confidence mixed folder is only suggested, never imported',
        () async {
      await writeMixedFolder('Random Songs', 6);

      final result = await LibraryScannerIsolate.scan(tempDir.path);

      expect(result.library!.folderPlaylists, isEmpty);
      expect(result.scanDiagnostics.autoImportedPlaylistFolders, isEmpty,
          reason: '6 files is below the auto-import minimum');
      expect(
        result.scanDiagnostics.playlistSuggestions.map((s) => s.name),
        ['Random Songs'],
      );
    });

    test('album folders are never auto-imported, even with many tracks',
        () async {
      for (var i = 1; i <= 10; i++) {
        await writeAudio(
          'Kanye West/808s and Heartbreak/track $i.mp3',
          title: 'Track $i',
          artist: 'Kanye West',
          album: '808s and Heartbreak',
        );
      }

      final result = await LibraryScannerIsolate.scan(tempDir.path);
      final library = result.library!;

      expect(library.folderPlaylists, isEmpty);
      expect(result.scanDiagnostics.autoImportedPlaylistFolders, isEmpty);
      expect(result.scanDiagnostics.playlistSuggestions, isEmpty);
      expect(
        library.albums.values.map((a) => a.title),
        contains('808s and Heartbreak'),
        reason: 'the folder stays an album',
      );
    });
  });

  test('an ignore decision blocks auto-import', () async {
    final gymPath = '${tempDir.path}/Gym';
    await writeMixedFolder('Gym', 8);

    final result = await LibraryScannerIsolate.scan(
      tempDir.path,
      ignoredSuggestionFolderPaths: [gymPath],
    );

    expect(result.library!.folderPlaylists, isEmpty);
    expect(result.scanDiagnostics.autoImportedPlaylistFolders, isEmpty);
    expect(result.scanDiagnostics.playlistSuggestions, isEmpty);
  });

  test(
      'a folder containing an explicit [PLAYLIST] folder is demoted to a '
      'suggestion instead of importing around it', () async {
    await writeMixedFolder('Gym', 8);
    await writeAudio(
      'Gym/[PLAYLIST] Cooldown/calm.mp3',
      title: 'Calm',
      artist: 'Chill Artist',
      album: 'Chill Album',
    );

    final result = await LibraryScannerIsolate.scan(tempDir.path);
    final library = result.library!;

    expect(
      library.folderPlaylists.map((p) => p.name).toList(),
      ['Cooldown'],
      reason: 'only the explicit marker folder imports',
    );
    expect(result.scanDiagnostics.autoImportedPlaylistFolders, isEmpty);
    expect(
      result.scanDiagnostics.playlistSuggestions.map((s) => s.name),
      ['Gym'],
      reason: 'the outer folder falls back to an advisory suggestion',
    );
  });

  test('explicit [PLAYLIST] folders and .m3u files still always import',
      () async {
    final marked = await writeAudio(
      '[PLAYLIST] Sleep/a.mp3',
      title: 'A',
      artist: 'X',
      album: 'Y',
    );
    final loose = await writeAudio(
      'loose.mp3',
      title: 'Loose',
      artist: 'L',
      album: 'M',
    );
    final m3u = File('${tempDir.path}/mix.m3u');
    await m3u.writeAsString('loose.mp3\n');

    final result = await LibraryScannerIsolate.scan(tempDir.path);
    final playlists = result.library!.folderPlaylists;

    expect(playlists.map((p) => p.name).toSet(), {'Sleep', 'mix'});
    expect(
      playlists.singleWhere((p) => p.name == 'Sleep').songIds,
      [defaultGenerateSongId(marked)],
    );
    expect(
      playlists.singleWhere((p) => p.name == 'mix').songIds,
      [defaultGenerateSongId(loose)],
    );
  });
}
