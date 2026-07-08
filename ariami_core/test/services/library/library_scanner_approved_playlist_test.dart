import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:test/test.dart';

import 'package:ariami_core/models/file_change.dart';
import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/change_processor.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';
import 'package:ariami_core/services/library/library_scanner_isolate.dart';

/// Full-scan behaviour of user-approved suggestion folders (the "import"
/// decision): they must scan exactly like [PLAYLIST] folders — additive
/// membership, natural order, artifact-tag guard — with a plain-basename
/// display name, and must stop being suggested. Ignored folders must stop
/// being suggested without becoming playlists.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ariami_approved_scan_');
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

  /// A folder shaped like a real playlist: five loose tracks from five
  /// different artists/albums with no track numbers.
  Future<List<String>> writeSuggestibleFolder(String folderName) async {
    final paths = <String>[];
    for (var i = 1; i <= 5; i++) {
      paths.add(await writeAudio(
        '$folderName/song $i.mp3',
        title: 'Song $i',
        artist: 'Artist $i',
        album: 'Album $i',
      ));
    }
    return paths;
  }

  test(
      'an approved folder scans exactly like a [PLAYLIST] folder: additive '
      'membership, plain basename name, stable ID, natural order', () async {
    final folderPath = '${tempDir.path}/Road Trip';
    final zebra = await writeAudio(
      'Road Trip/zebra.mp3',
      title: 'Zebra',
      artist: 'Ye',
      album: 'Cruel Summer',
    );
    final alpha = await writeAudio('Road Trip/alpha.mp3');
    await writeAudio(
      'Album/one.mp3',
      title: 'One',
      artist: 'Ye',
      album: 'Cruel Summer',
    );

    final result = await LibraryScannerIsolate.scan(
      tempDir.path,
      approvedPlaylistFolderPaths: [folderPath],
    );
    final library = result.library!;

    final playlist = library.folderPlaylists.single;
    expect(playlist.name, 'Road Trip',
        reason: 'approved folders keep their plain basename (no marker)');
    expect(playlist.id, FolderPlaylist.generateId(folderPath),
        reason: 'same ID scheme as marker folders, stable across scans');
    expect(
      playlist.songIds,
      [defaultGenerateSongId(alpha), defaultGenerateSongId(zebra)],
      reason: 'entries use natural path order',
    );

    // Additive: the tagged track still joins its album.
    expect(library.albums, hasLength(1));
    final album = library.albums.values.single;
    expect(album.title, 'Cruel Summer');
    expect(album.songs.map((s) => s.filePath), contains(zebra));
  });

  test(
      'the playlist-name-as-album artifact guard applies inside an approved '
      'folder', () async {
    final folderPath = '${tempDir.path}/Road Trip';
    // Downloader artifact shape: playlist name in every album tag, each
    // track keeping its own artist.
    for (var i = 1; i <= 3; i++) {
      await writeAudio(
        'Road Trip/song $i.mp3',
        title: 'Song $i',
        artist: 'Artist $i',
        album: 'Road Trip',
      );
    }

    final result = await LibraryScannerIsolate.scan(
      tempDir.path,
      approvedPlaylistFolderPaths: [folderPath],
    );
    final library = result.library!;

    expect(library.albums, isEmpty,
        reason: 'album tags matching the playlist name are artifacts');
    expect(library.standaloneSongs, hasLength(3));
    expect(library.folderPlaylists.single.songIds, hasLength(3));
  });

  test(
      'suggestions honour decisions: approved and ignored folders are not '
      'suggested, and a reset (no decision) re-suggests', () async {
    await writeSuggestibleFolder('Party Mix');
    final folderPath = '${tempDir.path}/Party Mix';

    // No decision: the folder is suggested and no playlist exists.
    final undecided = await LibraryScannerIsolate.scan(tempDir.path);
    expect(
      undecided.scanDiagnostics.playlistSuggestions.map((s) => s.folderPath),
      [folderPath],
    );
    expect(undecided.library!.folderPlaylists, isEmpty);

    // Approved: playlist exists, suggestion gone.
    final approved = await LibraryScannerIsolate.scan(
      tempDir.path,
      approvedPlaylistFolderPaths: [folderPath],
    );
    expect(approved.scanDiagnostics.playlistSuggestions, isEmpty);
    expect(approved.library!.folderPlaylists.single.name, 'Party Mix');
    expect(approved.library!.folderPlaylists.single.songIds, hasLength(5));

    // Ignored: no suggestion and no playlist.
    final ignored = await LibraryScannerIsolate.scan(
      tempDir.path,
      ignoredSuggestionFolderPaths: [folderPath],
    );
    expect(ignored.scanDiagnostics.playlistSuggestions, isEmpty);
    expect(ignored.library!.folderPlaylists, isEmpty);

    // Reset (decision cleared): suggested again, same as the first scan.
    final reset = await LibraryScannerIsolate.scan(tempDir.path);
    expect(
      reset.scanDiagnostics.playlistSuggestions.map((s) => s.folderPath),
      [folderPath],
    );
  });

  test(
      'an incremental rebuild preserves an approved playlist and its ID',
      () async {
    final folderPath = '${tempDir.path}/Road Trip';
    final paths = await writeSuggestibleFolder('Road Trip');

    final result = await LibraryScannerIsolate.scan(
      tempDir.path,
      approvedPlaylistFolderPaths: [folderPath],
    );
    final scannedLibrary = result.library!;
    final expectedIds = [for (final p in paths) defaultGenerateSongId(p)];
    expect(scannedLibrary.folderPlaylists.single.songIds, expectedIds);

    // Unrelated watcher change; the approved playlist must survive.
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

    final playlist = rebuilt.folderPlaylists.single;
    expect(playlist.id, FolderPlaylist.generateId(folderPath),
        reason: 'incremental rebuilds must keep the playlist ID stable');
    expect(playlist.name, 'Road Trip');
    expect(playlist.songIds, expectedIds,
        reason: 'membership and order survive unrelated changes');
  });
}
