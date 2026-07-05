List<String> reconcilePlaylistSongIds({
  required List<String> baseSongIds,
  required Set<String> liveSongIds,
  List<String>? editSongIds,
  List<String>? baseSnapshot,
}) {
  if (editSongIds == null) {
    return baseSongIds.where(liveSongIds.contains).toList(growable: false);
  }

  final effective =
      editSongIds.where(liveSongIds.contains).toList(growable: true);
  final effectiveSet = effective.toSet();
  final snapshotSet = (baseSnapshot ?? const <String>[]).toSet();
  for (final id in baseSongIds) {
    if (!liveSongIds.contains(id)) continue;
    if (snapshotSet.contains(id)) continue;
    if (effectiveSet.contains(id)) continue;
    effective.add(id);
    effectiveSet.add(id);
  }
  return List<String>.unmodifiable(effective);
}

String reconcilePlaylistName({
  required String baseName,
  String? editName,
}) =>
    editName ?? baseName;
