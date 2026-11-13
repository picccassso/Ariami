import 'dart:convert';

import 'package:ariami_core/models/library_curation.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/connection_service.dart';

/// Client-side state & offline cache for the signed-in user's library curation
/// rules (`/api/v2/curation`).
class LibraryCurationService extends ChangeNotifier {
  static final LibraryCurationService _instance =
      LibraryCurationService._internal();
  factory LibraryCurationService() => _instance;
  LibraryCurationService._internal();

  static const String _prefsKey = 'ariami_user_library_curation_v1';

  UserLibraryCuration _curation = UserLibraryCuration.defaultForUser(
    '',
    onboardingCompleted: true,
  );
  LibraryCurationFilter _filter = LibraryCurationFilter.unrestricted;
  bool _initialized = false;
  bool _loadedFromServer = false;

  UserLibraryCuration get curation => _curation;
  LibraryCurationFilter get filter => _filter;
  bool get isLoaded => _loadedFromServer;

  bool get needsOnboarding =>
      _loadedFromServer && !_curation.onboardingCompleted;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) {
          _apply(UserLibraryCuration.fromJson(decoded), notify: false);
        }
      }
    } catch (e) {
      debugPrint('[LibraryCurationService] Failed to restore cache: $e');
    }
  }

  Future<void> loadFromServer() async {
    final client = ConnectionService().apiClient;
    if (client == null) return;
    try {
      final next = await client.getCuration();
      _loadedFromServer = true;
      _apply(next);
      await _persist();
    } catch (e) {
      debugPrint('[LibraryCurationService] Failed to load curation: $e');
    }
  }

  Future<UserLibraryCuration> saveCuration({
    required LibraryCurationMode mode,
    required List<CurationRuleEntry> rules,
    bool onboardingCompleted = true,
  }) async {
    final client = ConnectionService().apiClient;
    if (client == null) {
      throw StateError('Connect to your server to save library curation');
    }
    final saved = await client.putCuration(<String, dynamic>{
      'mode': mode.name,
      'onboardingCompleted': onboardingCompleted,
      'rules': rules.map((r) => r.toJson()).toList(growable: false),
    });
    _loadedFromServer = true;
    _apply(saved);
    await _persist();
    return saved;
  }

  Future<void> completeOnboardingFull() async {
    await saveCuration(
      mode: LibraryCurationMode.full,
      rules: _curation.rules,
      onboardingCompleted: true,
    );
  }

  Future<void> addTargetsToLibrary({
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

    await saveCuration(
      mode: _curation.mode,
      rules: nextRules,
      onboardingCompleted: true,
    );
  }

  void _apply(UserLibraryCuration next, {bool notify = true}) {
    _curation = next;
    _filter = next.buildFilter();
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, json.encode(_curation.toJson()));
    } catch (e) {
      debugPrint('[LibraryCurationService] Failed to persist cache: $e');
    }
  }
}
