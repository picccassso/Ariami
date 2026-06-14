/// Result of remapping album-keyed library state to new album IDs.
class AlbumKeyRemapResult {
  final Set<String> pins;
  final Map<String, DateTime> recents;
  final bool pinsChanged;
  final bool recentsChanged;

  const AlbumKeyRemapResult({
    required this.pins,
    required this.recents,
    required this.pinsChanged,
    required this.recentsChanged,
  });

  bool get hasChanges => pinsChanged || recentsChanged;
}

String? _albumIdFromKey(String key) =>
    key.startsWith('album:') ? key.substring('album:'.length) : null;

/// Re-points `album:<id>` keys in pins and recents from old album IDs to current
/// ones using the exact [oldToNew] pairs. Playlist keys (and any non-album keys)
/// are left untouched. When both the old and new key exist in recents, the most
/// recent timestamp wins.
AlbumKeyRemapResult remapAlbumKeys({
  required Set<String> pins,
  required Map<String, DateTime> recents,
  required Map<String, String> oldToNew,
}) {
  if (oldToNew.isEmpty) {
    return AlbumKeyRemapResult(
      pins: pins,
      recents: recents,
      pinsChanged: false,
      recentsChanged: false,
    );
  }

  var pinsChanged = false;
  final updatedPins = <String>{};
  for (final key in pins) {
    final albumId = _albumIdFromKey(key);
    final newId = albumId == null ? null : oldToNew[albumId];
    if (newId != null) {
      updatedPins.add('album:$newId');
      pinsChanged = true;
    } else {
      updatedPins.add(key);
    }
  }

  var recentsChanged = false;
  final updatedRecents = <String, DateTime>{};
  recents.forEach((key, value) {
    final albumId = _albumIdFromKey(key);
    final newId = albumId == null ? null : oldToNew[albumId];
    final targetKey = newId != null ? 'album:$newId' : key;
    if (newId != null) recentsChanged = true;
    final existing = updatedRecents[targetKey];
    if (existing == null || value.isAfter(existing)) {
      updatedRecents[targetKey] = value;
    }
  });

  return AlbumKeyRemapResult(
    pins: updatedPins,
    recents: updatedRecents,
    pinsChanged: pinsChanged,
    recentsChanged: recentsChanged,
  );
}
