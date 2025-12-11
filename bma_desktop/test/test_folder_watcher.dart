import 'dart:io';
import 'package:bma_core/bma_core.dart';

void main() async {
  print('=== Folder Watcher Test ===\n');

  // Get folder path
  print('Enter the path to a folder to watch:');
  final folderPath = stdin.readLineSync()?.trim();

  if (folderPath == null || folderPath.isEmpty) {
    print('Error: No path provided');
    return;
  }

  final folder = Directory(folderPath);
  if (!await folder.exists()) {
    print('Error: Directory does not exist');
    return;
  }

  print('\n--- Starting Folder Watcher ---');

  final watcher = FolderWatcher();

  // Listen for changes
  int changeCount = 0;
  watcher.changes.listen((changes) {
    changeCount++;
    print('\n📦 Batch #$changeCount - Received ${changes.length} file change(s):');
    for (final change in changes) {
      final fileName = change.path.split(Platform.pathSeparator).last;
      final icon = _getIcon(change.type);
      print('  $icon ${change.type.name.toUpperCase()}: $fileName');
      print('     Path: ${change.path}');
      print('     Time: ${change.timestamp}');
    }
  });

  watcher.startWatching(folderPath);

  print('\n✅ Now watching: $folderPath');
  print('\nTest actions you can perform:');
  print('  1. Add a new .mp3 file to the folder');
  print('  2. Modify an existing .mp3 file');
  print('  3. Delete an .mp3 file');
  print('  4. Rename an .mp3 file');
  print('\nNotes:');
  print('  - Changes are batched with a 2-second debounce');
  print('  - Only audio files are monitored');
  print('  - Hidden/temporary files are ignored');
  print('\nPress Ctrl+C to stop watching.\n');

  // Keep the program running
  await Future.delayed(Duration(hours: 1));

  watcher.dispose();
}

String _getIcon(FileChangeType type) {
  switch (type) {
    case FileChangeType.added:
      return '➕';
    case FileChangeType.removed:
      return '❌';
    case FileChangeType.modified:
      return '✏️ ';
    case FileChangeType.renamed:
      return '🔄';
  }
}
