import 'package:ariami_core/services/playlists/created_playlist_id.dart';
import 'package:ariami_core/services/stats/credited_artist_splitter.dart';

/// Controls how a user's personal library view relates to the master catalog.
enum LibraryCurationMode {
  /// Default for server owners: everything scanned into the server catalog is
  /// visible unless explicitly excluded.
  full('full'),

  /// Allowlist mode: only artists, albums, server playlists, and standalone
  /// songs matching explicit include rules (or credited to an included artist)
  /// are shown in the user's library.
  curated('curated');

  const LibraryCurationMode(this.wireName);

  final String wireName;

  static LibraryCurationMode fromWire(String? value) {
    switch (value) {
      case 'curated':
        return LibraryCurationMode.curated;
      case 'full':
      default:
        return LibraryCurationMode.full;
    }
  }
}

/// Entity types supported by per-user curation rules.
enum CurationTargetType {
  artist('artist'),
  album('album'),
  song('song'),
  playlist('playlist');

  const CurationTargetType(this.wireName);

  final String wireName;

  static CurationTargetType? tryFromWire(String? value) {
    switch (value) {
      case 'artist':
        return CurationTargetType.artist;
      case 'album':
        return CurationTargetType.album;
      case 'song':
        return CurationTargetType.song;
      case 'playlist':
        return CurationTargetType.playlist;
      default:
        return null;
    }
  }
}

/// Whether a curation rule adds an entity to the user's library or removes it.
enum CurationRuleAction {
  include('include'),
  exclude('exclude');

  const CurationRuleAction(this.wireName);

  final String wireName;

  static CurationRuleAction? tryFromWire(String? value) {
    switch (value) {
      case 'include':
        return CurationRuleAction.include;
      case 'exclude':
        return CurationRuleAction.exclude;
      default:
        return null;
    }
  }
}

/// Single rule inside a user's library curation configuration.
class CurationRuleEntry {
  const CurationRuleEntry({
    required this.targetType,
    required this.targetId,
    required this.action,
    required this.updatedAt,
    this.sourceDeviceId,
    this.displayLabel,
  });

  final CurationTargetType targetType;
  final String targetId;
  final CurationRuleAction action;
  final DateTime updatedAt;
  final String? sourceDeviceId;
  final String? displayLabel;

  /// Canonical target identifier used for storage deduplication and matching.
  static String normalizeTargetId(
    CurationTargetType targetType,
    String rawTargetId,
  ) {
    final trimmed = rawTargetId.trim();
    if (targetType == CurationTargetType.artist) {
      return normalizeArtistKey(trimmed);
    }
    return trimmed;
  }

  String get normalizedTargetId => normalizeTargetId(targetType, targetId);

  String get key => '${targetType.wireName}:$normalizedTargetId';

  CurationRuleEntry normalized() {
    final norm = normalizedTargetId;
    final preservedLabel = displayLabel ??
        (targetType == CurationTargetType.artist && targetId.trim().isNotEmpty
            ? targetId.trim()
            : null);
    return CurationRuleEntry(
      targetType: targetType,
      targetId: norm,
      action: action,
      updatedAt: updatedAt,
      sourceDeviceId: sourceDeviceId,
      displayLabel: preservedLabel,
    );
  }

  CurationRuleEntry copyWith({
    CurationTargetType? targetType,
    String? targetId,
    CurationRuleAction? action,
    DateTime? updatedAt,
    String? sourceDeviceId,
    String? displayLabel,
  }) {
    return CurationRuleEntry(
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      action: action ?? this.action,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      displayLabel: displayLabel ?? this.displayLabel,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'targetType': targetType.wireName,
        'targetId': targetId,
        'action': action.wireName,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (sourceDeviceId != null) 'sourceDeviceId': sourceDeviceId,
        if (displayLabel != null) 'displayLabel': displayLabel,
      };

  static CurationRuleEntry? tryFromJson(Map<String, dynamic> json) {
    final targetType =
        CurationTargetType.tryFromWire(json['targetType'] as String?);
    final action = CurationRuleAction.tryFromWire(json['action'] as String?);
    final rawTargetId = json['targetId'] as String?;
    if (targetType == null ||
        action == null ||
        rawTargetId == null ||
        rawTargetId.trim().isEmpty) {
      return null;
    }
    final parsedUpdatedAt =
        DateTime.tryParse((json['updatedAt'] as String?) ?? '')?.toUtc() ??
            DateTime.now().toUtc();
    return CurationRuleEntry(
      targetType: targetType,
      targetId: rawTargetId.trim(),
      action: action,
      updatedAt: parsedUpdatedAt,
      sourceDeviceId: (json['sourceDeviceId'] as String?)?.trim(),
      displayLabel: (json['displayLabel'] as String?)?.trim(),
    ).normalized();
  }
}

/// Complete per-user library curation snapshot exchanged over HTTP & SQLite.
class UserLibraryCuration {
  const UserLibraryCuration({
    required this.userId,
    required this.mode,
    required this.onboardingCompleted,
    required this.revision,
    required this.updatedAt,
    required this.rules,
  });

  static const int currentSchemaVersion = 1;

  final String userId;
  final LibraryCurationMode mode;
  final bool onboardingCompleted;
  final int revision;
  final DateTime updatedAt;
  final List<CurationRuleEntry> rules;

  factory UserLibraryCuration.defaultForUser(
    String userId, {
    LibraryCurationMode mode = LibraryCurationMode.full,
    bool onboardingCompleted = false,
    int revision = 0,
    DateTime? updatedAt,
    List<CurationRuleEntry> rules = const <CurationRuleEntry>[],
  }) {
    return UserLibraryCuration(
      userId: userId,
      mode: mode,
      onboardingCompleted: onboardingCompleted,
      revision: revision,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
      rules: rules,
    );
  }

  LibraryCurationFilter buildFilter() =>
      LibraryCurationFilter.fromCuration(this);

  UserLibraryCuration copyWith({
    String? userId,
    LibraryCurationMode? mode,
    bool? onboardingCompleted,
    int? revision,
    DateTime? updatedAt,
    List<CurationRuleEntry>? rules,
  }) {
    return UserLibraryCuration(
      userId: userId ?? this.userId,
      mode: mode ?? this.mode,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      rules: rules ?? this.rules,
    );
  }

  Map<String, dynamic> toSummaryJson() {
    var includedArtists = 0;
    var includedAlbums = 0;
    var includedSongs = 0;
    var includedPlaylists = 0;
    var excludedCount = 0;

    for (final rule in rules) {
      if (rule.action == CurationRuleAction.exclude) {
        excludedCount++;
        continue;
      }
      switch (rule.targetType) {
        case CurationTargetType.artist:
          includedArtists++;
          break;
        case CurationTargetType.album:
          includedAlbums++;
          break;
        case CurationTargetType.song:
          includedSongs++;
          break;
        case CurationTargetType.playlist:
          includedPlaylists++;
          break;
      }
    }

    return <String, dynamic>{
      'mode': mode.wireName,
      'onboardingCompleted': onboardingCompleted,
      'revision': revision,
      'ruleCount': rules.length,
      'includedArtists': includedArtists,
      'includedAlbums': includedAlbums,
      'includedSongs': includedSongs,
      'includedPlaylists': includedPlaylists,
      'excludedCount': excludedCount,
    };
  }

  static String formatSummaryLabel(Map<String, dynamic>? summary) {
    if (summary == null) return 'Include Everything';
    final mode = LibraryCurationMode.fromWire(summary['mode'] as String?);
    if (mode == LibraryCurationMode.full) {
      final excluded = (summary['excludedCount'] as num?)?.toInt() ?? 0;
      return excluded > 0
          ? 'Include Everything ($excluded excluded)'
          : 'Include Everything';
    }
    final artists = (summary['includedArtists'] as num?)?.toInt() ?? 0;
    final albums = (summary['includedAlbums'] as num?)?.toInt() ?? 0;
    final playlists = (summary['includedPlaylists'] as num?)?.toInt() ?? 0;
    final songs = (summary['includedSongs'] as num?)?.toInt() ?? 0;
    final parts = <String>[
      if (artists > 0) '$artists ${artists == 1 ? 'artist' : 'artists'}',
      if (albums > 0) '$albums ${albums == 1 ? 'album' : 'albums'}',
      if (playlists > 0)
        '$playlists ${playlists == 1 ? 'playlist' : 'playlists'}',
      if (songs > 0) '$songs ${songs == 1 ? 'song' : 'songs'}',
    ];
    if (parts.isEmpty) return 'Curated · Empty';
    return 'Curated · ${parts.join(', ')}';
  }

  Map<String, dynamic> toJson({bool includeSchemaVersion = true}) =>
      <String, dynamic>{
        if (includeSchemaVersion) 'schemaVersion': currentSchemaVersion,
        'userId': userId,
        'mode': mode.wireName,
        'onboardingCompleted': onboardingCompleted,
        'revision': revision,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'rules': rules.map((r) => r.toJson()).toList(growable: false),
      };

  factory UserLibraryCuration.fromJson(
    Map<String, dynamic> json, {
    String fallbackUserId = '',
  }) {
    final userId = ((json['userId'] as String?) ?? fallbackUserId).trim();
    final mode = LibraryCurationMode.fromWire(json['mode'] as String?);
    final onboardingCompleted = json['onboardingCompleted'] as bool? ?? false;
    final revision = (json['revision'] as num?)?.toInt() ?? 0;
    final updatedAt =
        DateTime.tryParse((json['updatedAt'] as String?) ?? '')?.toUtc() ??
            DateTime.now().toUtc();
    final rawRules = json['rules'] as List<dynamic>? ?? const <dynamic>[];
    final rules = <CurationRuleEntry>[];
    for (final item in rawRules) {
      if (item is Map) {
        final parsed = CurationRuleEntry.tryFromJson(
          Map<String, dynamic>.from(item),
        );
        if (parsed != null) {
          rules.add(parsed);
        }
      }
    }
    return UserLibraryCuration(
      userId: userId,
      mode: mode,
      onboardingCompleted: onboardingCompleted,
      revision: revision,
      updatedAt: updatedAt,
      rules: rules,
    );
  }
}

/// Evaluates whether artists, albums, songs, and server playlists belong to a
/// user's curated library view.
///
/// Precedence (most specific wins):
/// 1. Explicit song exclude / include
/// 2. Explicit album exclude / include
/// 3. Artist credit rules (via [CreditedArtistSplitter] + [normalizeArtistKey])
/// 4. [LibraryCurationMode] fallback (`full` includes, `curated` excludes)
class LibraryCurationFilter {
  const LibraryCurationFilter({
    this.mode = LibraryCurationMode.full,
    this.includedArtists = const <String>{},
    this.excludedArtists = const <String>{},
    this.includedAlbums = const <String>{},
    this.excludedAlbums = const <String>{},
    this.includedSongs = const <String>{},
    this.excludedSongs = const <String>{},
    this.includedPlaylists = const <String>{},
    this.excludedPlaylists = const <String>{},
  });

  static final CreditedArtistSplitter _splitter = CreditedArtistSplitter();

  final LibraryCurationMode mode;
  final Set<String> includedArtists;
  final Set<String> excludedArtists;
  final Set<String> includedAlbums;
  final Set<String> excludedAlbums;
  final Set<String> includedSongs;
  final Set<String> excludedSongs;
  final Set<String> includedPlaylists;
  final Set<String> excludedPlaylists;

  static const LibraryCurationFilter unrestricted = LibraryCurationFilter();

  factory LibraryCurationFilter.fromCuration(UserLibraryCuration curation) {
    final includedArtists = <String>{};
    final excludedArtists = <String>{};
    final includedAlbums = <String>{};
    final excludedAlbums = <String>{};
    final includedSongs = <String>{};
    final excludedSongs = <String>{};
    final includedPlaylists = <String>{};
    final excludedPlaylists = <String>{};

    for (final rule in curation.rules) {
      final id = rule.normalizedTargetId;
      if (id.isEmpty) continue;
      final isInclude = rule.action == CurationRuleAction.include;
      switch (rule.targetType) {
        case CurationTargetType.artist:
          (isInclude ? includedArtists : excludedArtists).add(id);
          break;
        case CurationTargetType.album:
          (isInclude ? includedAlbums : excludedAlbums).add(id);
          break;
        case CurationTargetType.song:
          (isInclude ? includedSongs : excludedSongs).add(id);
          break;
        case CurationTargetType.playlist:
          (isInclude ? includedPlaylists : excludedPlaylists).add(id);
          break;
      }
    }

    return LibraryCurationFilter(
      mode: curation.mode,
      includedArtists: includedArtists,
      excludedArtists: excludedArtists,
      includedAlbums: includedAlbums,
      excludedAlbums: excludedAlbums,
      includedSongs: includedSongs,
      excludedSongs: excludedSongs,
      includedPlaylists: includedPlaylists,
      excludedPlaylists: excludedPlaylists,
    );
  }

  bool get isPassThrough =>
      mode == LibraryCurationMode.full &&
      excludedArtists.isEmpty &&
      excludedAlbums.isEmpty &&
      excludedSongs.isEmpty &&
      excludedPlaylists.isEmpty;

  static List<CreditedArtist> splitArtists(String? rawArtist) =>
      _splitter.split(rawArtist);

  static List<String> artistKeysFor(String? rawArtist) =>
      _splitter.split(rawArtist).map((credit) => credit.key).toList();

  bool isArtistExplicitlyIncluded(String? artist) =>
      artistKeysFor(artist).any(includedArtists.contains);

  bool isArtistExplicitlyExcluded(String? artist) =>
      artistKeysFor(artist).any(excludedArtists.contains);

  bool isAlbumExplicitlyIncluded(String albumId) =>
      includedAlbums.contains(albumId);

  bool isAlbumExplicitlyExcluded(String albumId) =>
      excludedAlbums.contains(albumId);

  bool isSongExplicitlyIncluded(String songId) =>
      includedSongs.contains(songId);

  bool isSongExplicitlyExcluded(String songId) =>
      excludedSongs.contains(songId);

  bool isPlaylistExplicitlyIncluded(String playlistId) =>
      includedPlaylists.contains(playlistId);

  bool isPlaylistExplicitlyExcluded(String playlistId) =>
      excludedPlaylists.contains(playlistId);

  bool isAlbumIncluded({
    required String albumId,
    String? artist,
  }) {
    if (excludedAlbums.contains(albumId)) return false;
    if (includedAlbums.contains(albumId)) return true;

    final keys = artistKeysFor(artist);
    if (keys.any(excludedArtists.contains)) return false;

    if (mode == LibraryCurationMode.full) {
      return true;
    }
    return keys.any(includedArtists.contains);
  }

  bool isSongIncluded({
    required String songId,
    String? artist,
    String? albumId,
    String? albumArtist,
  }) {
    if (excludedSongs.contains(songId)) return false;
    if (includedSongs.contains(songId)) return true;

    if (albumId != null && albumId.isNotEmpty) {
      if (excludedAlbums.contains(albumId)) return false;
      if (includedAlbums.contains(albumId)) return true;
    }

    final songKeys = artistKeysFor(artist);
    if (songKeys.any(excludedArtists.contains)) return false;

    final albumKeys = (albumArtist != null && albumArtist.trim().isNotEmpty)
        ? artistKeysFor(albumArtist)
        : const <String>[];

    if (mode == LibraryCurationMode.full) {
      if (albumKeys.any(excludedArtists.contains) &&
          !songKeys.any(includedArtists.contains)) {
        return false;
      }
      return true;
    }

    if (songKeys.any(includedArtists.contains)) return true;
    if (albumKeys.any(excludedArtists.contains)) return false;
    return albumKeys.any(includedArtists.contains);
  }

  bool isServerPlaylistIncluded(String playlistId) {
    if (isAccountOwnedPlaylistId(playlistId)) {
      return !excludedPlaylists.contains(playlistId);
    }
    if (excludedPlaylists.contains(playlistId)) return false;
    if (mode == LibraryCurationMode.full) return true;
    return includedPlaylists.contains(playlistId);
  }

  List<T> filterAlbums<T>(
    Iterable<T> albums, {
    required String Function(T) idOf,
    required String? Function(T) artistOf,
  }) {
    if (isPassThrough) return albums.toList(growable: false);
    return albums
        .where((album) => isAlbumIncluded(
              albumId: idOf(album),
              artist: artistOf(album),
            ))
        .toList(growable: false);
  }

  List<T> filterSongs<T>(
    Iterable<T> songs, {
    required String Function(T) idOf,
    required String? Function(T) artistOf,
    required String? Function(T) albumIdOf,
    String? Function(T)? albumArtistOf,
  }) {
    if (isPassThrough) return songs.toList(growable: false);
    return songs
        .where((song) => isSongIncluded(
              songId: idOf(song),
              artist: artistOf(song),
              albumId: albumIdOf(song),
              albumArtist: albumArtistOf?.call(song),
            ))
        .toList(growable: false);
  }

  List<T> filterPlaylists<T>(
    Iterable<T> playlists, {
    required String Function(T) idOf,
  }) {
    if (isPassThrough) return playlists.toList(growable: false);
    return playlists
        .where((playlist) => isServerPlaylistIncluded(idOf(playlist)))
        .toList(growable: false);
  }
}
