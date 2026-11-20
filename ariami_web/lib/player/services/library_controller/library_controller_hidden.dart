part of '../library_controller.dart';

/// Account-synced hiding: albums, playlists and artists the user has chosen to
/// keep out of the library sidebar.
///
/// Hiding is presentation only. A hidden album still plays, still appears in
/// Browse, search and on artist pages, and its songs stay in All Songs — the
/// sidebar is the one list that honours it. That is also why the filtering
/// lives in the sidebar widget rather than in the [albums] / [playlists] /
/// [artists] getters: every other view is meant to keep showing these.
///
/// Not to be confused with `_hiddenPlaylistIds`, which is this device's record
/// of server playlists deleted from the desktop library.
extension _LibraryControllerHidden on LibraryController {
  Future<void> _refreshHidden() async {
    final client = _client;
    if (client == null) return;
    final results = await Future.wait<Object?>([
      client.fetchHidden(),
      _fetchCurationOrKeep(client),
    ]);
    if (!identical(client, _client)) return;
    _applyHidden(results[0] as List<HiddenMediaItem>);
    if (results[1] case final UserLibraryCuration curation) {
      _applyCuration(curation);
    }
    _notifyListeners();
  }

  Future<void> _refreshCuration() async {
    final client = _client;
    if (client == null) return;
    final results = await Future.wait<Object?>([
      client.fetchCuration(),
      _fetchHiddenOrKeep(client),
    ]);
    if (!identical(client, _client)) return;
    _applyCuration(results[0] as UserLibraryCuration);
    if (results[1] case final List<HiddenMediaItem> hidden) {
      _applyHidden(hidden);
    }
    _notifyListeners();
  }

  void _applyCuration(UserLibraryCuration curation) {
    _curation = curation;
    _curationFilter = curation.buildFilter();
    _curationVersion++;
    _curationLoaded = true;
  }

  Future<void> _saveCuration({
    required LibraryCurationMode mode,
    required List<CurationRuleEntry> rules,
    bool onboardingCompleted = true,
  }) async {
    final client = _client;
    if (client == null) return;
    final saved = await client.putCuration(<String, dynamic>{
      'mode': mode.name,
      'onboardingCompleted': onboardingCompleted,
      'rules': rules.map((r) => r.toJson()).toList(growable: false),
    });
    if (!identical(client, _client)) return;
    _applyCuration(saved);
    final hidden = await _fetchHiddenOrKeep(client);
    if (!identical(client, _client)) return;
    if (hidden != null) {
      _applyHidden(hidden);
    }
    _notifyListeners();
  }

  Future<void> _addTargetsToLibrary({
    List<String> artists = const <String>[],
    List<String> albumIds = const <String>[],
    List<String> songIds = const <String>[],
    List<String> playlistIds = const <String>[],
  }) async {
    final nextRules = List<CurationRuleEntry>.from(_curation.rules);
    void upsertInclude(
      CurationTargetType type,
      String targetId, {
      String? displayLabel,
    }) {
      final candidate = CurationRuleEntry(
        targetType: type,
        targetId: targetId,
        action: CurationRuleAction.include,
        updatedAt: DateTime.now().toUtc(),
        displayLabel: displayLabel,
      ).normalized();
      nextRules.removeWhere(
        (r) =>
            r.targetType == type &&
            r.normalizedTargetId == candidate.normalizedTargetId,
      );
      if (_curation.mode == LibraryCurationMode.curated) {
        nextRules.add(candidate);
      }
    }

    for (final artist in artists) {
      upsertInclude(CurationTargetType.artist, artist, displayLabel: artist);
    }
    for (final albumId in albumIds) {
      upsertInclude(CurationTargetType.album, albumId);
    }
    for (final songId in songIds) {
      upsertInclude(CurationTargetType.song, songId);
    }
    for (final playlistId in playlistIds) {
      upsertInclude(CurationTargetType.playlist, playlistId);
    }
    await _saveCuration(
      mode: _curation.mode,
      rules: nextRules,
      onboardingCompleted: true,
    );
  }

  void _applyHidden(List<HiddenMediaItem> hidden) {
    _hiddenItems = List<HiddenMediaItem>.unmodifiable(hidden);
    _hiddenKeys
      ..clear()
      ..addAll(hidden.map((item) => item.key));
  }

  /// Hides a batch — one request for a whole multi-selection.
  ///
  /// Applied locally first: the point of the action is that the rows leave the
  /// list immediately, so waiting for the round trip would make it feel broken.
  /// Only the keys this call actually added are rolled back on failure, so a
  /// concurrent hide of the same target from another device survives.
  Future<void> _hideItems(
    Iterable<({String type, String targetId})> targets,
  ) async {
    final client = _client;
    if (client == null) return;
    final resolved = targets
        .where((target) =>
            HiddenMediaItem.supportedTypes.contains(target.type) &&
            target.targetId.trim().isNotEmpty)
        .toList(growable: false);
    if (resolved.isEmpty) return;

    final added = <String>[
      for (final target in resolved)
        if (_hiddenKeys.add('${target.type}:${target.targetId}'))
          '${target.type}:${target.targetId}',
    ];
    _notifyListeners();
    try {
      await client.hide(resolved);
    } catch (_) {
      _hiddenKeys.removeAll(added);
      _notifyListeners();
      rethrow;
    }
    await _refreshHidden();
  }

  Future<void> _unhideItem(String type, String targetId) async {
    final client = _client;
    if (client == null) return;
    final key = '$type:$targetId';
    final removed = _hiddenKeys.remove(key);
    _notifyListeners();
    try {
      await client.unhide(type, targetId);
    } catch (_) {
      if (removed) _hiddenKeys.add(key);
      _notifyListeners();
      rethrow;
    }
    await _refreshHidden();
  }
}
