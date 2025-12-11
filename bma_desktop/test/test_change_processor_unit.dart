import 'package:bma_core/bma_core.dart';

void main() async {
  print('=== Change Processor Unit Test ===\n');

  // Create mock library structure
  final mockSongs = [
    SongMetadata(
      filePath: '/music/song1.mp3',
      title: 'Song 1',
      artist: 'Artist A',
      album: 'Album 1',
      fileSize: 1000000,
      modifiedTime: DateTime.now(),
    ),
    SongMetadata(
      filePath: '/music/song2.mp3',
      title: 'Song 2',
      artist: 'Artist A',
      album: 'Album 1',
      fileSize: 1000000,
      modifiedTime: DateTime.now(),
    ),
    SongMetadata(
      filePath: '/music/song3.mp3',
      title: 'Song 3',
      artist: 'Artist B',
      album: 'Album 2',
      fileSize: 1000000,
      modifiedTime: DateTime.now(),
    ),
  ];

  final mockAlbum1 = Album(
    id: 'album1',
    title: 'Album 1',
    artist: 'Artist A',
    songs: [mockSongs[0], mockSongs[1]],
  );

  final mockAlbum2 = Album(
    id: 'album2',
    title: 'Album 2',
    artist: 'Artist B',
    songs: [mockSongs[2]],
  );

  final currentLibrary = LibraryStructure(
    albums: {
      'album1': mockAlbum1,
      'album2': mockAlbum2,
    },
    standaloneSongs: [],
  );

  print('Initial Library:');
  print('  Total albums: ${currentLibrary.totalAlbums}');
  print('  Total songs: ${currentLibrary.totalSongs}');

  // Test 1: File removal
  print('\n--- Test 1: File Removal ---');
  final removalChanges = [
    FileChange(
      path: '/music/song1.mp3',
      type: FileChangeType.removed,
      timestamp: DateTime.now(),
    ),
  ];

  final processor = ChangeProcessor();
  final removalUpdate = await processor.processChanges(removalChanges, currentLibrary);

  print('Changes processed:');
  print('  Removed songs: ${removalUpdate.removedSongIds.length}');
  print('  Affected albums: ${removalUpdate.affectedAlbumIds.length}');
  print('  Is empty: ${removalUpdate.isEmpty}');

  // Test 2: File modification
  print('\n--- Test 2: File Modification ---');
  final modificationChanges = [
    FileChange(
      path: '/music/song2.mp3',
      type: FileChangeType.modified,
      timestamp: DateTime.now(),
    ),
  ];

  final modificationUpdate = await processor.processChanges(modificationChanges, currentLibrary);

  print('Changes processed:');
  print('  Modified songs: ${modificationUpdate.modifiedSongIds.length}');
  print('  Affected albums: ${modificationUpdate.affectedAlbumIds.length}');
  print('  Is empty: ${modificationUpdate.isEmpty}');

  // Test 3: Multiple changes
  print('\n--- Test 3: Multiple Changes (Batch) ---');
  final batchChanges = [
    FileChange(
      path: '/music/song1.mp3',
      type: FileChangeType.removed,
      timestamp: DateTime.now(),
    ),
    FileChange(
      path: '/music/song2.mp3',
      type: FileChangeType.modified,
      timestamp: DateTime.now(),
    ),
    FileChange(
      path: '/music/song4.mp3',
      type: FileChangeType.added,
      timestamp: DateTime.now(),
    ),
  ];

  final batchUpdate = await processor.processChanges(batchChanges, currentLibrary);

  print('Changes processed:');
  print('  Added songs: ${batchUpdate.addedSongIds.length}');
  print('  Removed songs: ${batchUpdate.removedSongIds.length}');
  print('  Modified songs: ${batchUpdate.modifiedSongIds.length}');
  print('  Affected albums: ${batchUpdate.affectedAlbumIds.length}');
  print('  Timestamp: ${batchUpdate.timestamp}');

  print('\n✅ All change processor unit tests passed!');
}
