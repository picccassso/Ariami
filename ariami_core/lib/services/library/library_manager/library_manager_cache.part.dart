part of '../library_manager.dart';

extension _LibraryManagerCachePart on LibraryManager {
  Future<void> _clearMetadataCacheImpl() async {
    if (_metadataCache != null) {
      await _metadataCache!.clear();
      print('[LibraryManager] Metadata cache cleared');
    }
  }
}
