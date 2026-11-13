import 'package:ariami_core/models/library_curation.dart';

class CurationCatalogAlbum {
  const CurationCatalogAlbum({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    this.songCount = 0,
  });

  final String id;
  final String title;
  final String artist;
  final int? year;
  final int songCount;

  factory CurationCatalogAlbum.fromJson(Map<String, dynamic> json) {
    return CurationCatalogAlbum(
      id: (json['id'] as String? ?? '').trim(),
      title: (json['title'] as String? ?? 'Unknown Album').trim(),
      artist: (json['artist'] as String? ?? 'Unknown Artist').trim(),
      year: (json['year'] as num?)?.toInt(),
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CurationCatalogPlaylist {
  const CurationCatalogPlaylist({
    required this.id,
    required this.name,
    this.songCount = 0,
  });

  final String id;
  final String name;
  final int songCount;

  factory CurationCatalogPlaylist.fromJson(Map<String, dynamic> json) {
    return CurationCatalogPlaylist(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? 'Playlist').trim(),
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CurationCatalogSong {
  const CurationCatalogSong({
    required this.id,
    required this.title,
    required this.artist,
    this.albumId,
    this.albumTitle,
    this.durationSeconds = 0,
    this.trackNumber,
  });

  final String id;
  final String title;
  final String artist;
  final String? albumId;
  final String? albumTitle;
  final int durationSeconds;
  final int? trackNumber;

  factory CurationCatalogSong.fromJson(Map<String, dynamic> json) {
    final rawAlbumId = json['albumId'] as String?;
    final rawAlbumTitle = json['albumTitle'] as String?;
    return CurationCatalogSong(
      id: (json['id'] as String? ?? '').trim(),
      title: (json['title'] as String? ?? 'Unknown Song').trim(),
      artist: (json['artist'] as String? ?? 'Unknown Artist').trim(),
      albumId: rawAlbumId == null || rawAlbumId.trim().isEmpty
          ? null
          : rawAlbumId.trim(),
      albumTitle: rawAlbumTitle == null || rawAlbumTitle.trim().isEmpty
          ? null
          : rawAlbumTitle.trim(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      trackNumber: (json['trackNumber'] as num?)?.toInt(),
    );
  }
}

class CurationArtistGroup {
  const CurationArtistGroup({
    required this.key,
    required this.displayName,
    required this.albums,
    required this.standaloneSongs,
  });

  final String key;
  final String displayName;
  final List<CurationCatalogAlbum> albums;
  final List<CurationCatalogSong> standaloneSongs;

  int get totalItems => albums.length + standaloneSongs.length;
}

enum CurationArtistSelectionState {
  none,
  partial,
  all;

  bool? toTristateBool() {
    switch (this) {
      case CurationArtistSelectionState.all:
        return true;
      case CurationArtistSelectionState.none:
        return false;
      case CurationArtistSelectionState.partial:
        return null;
    }
  }
}

/// Mutable draft state used by all library curation picker UIs (`ariami_cli`,
/// `ariami_desktop_premium`, `ariami_mobile`) so selection, mode switching,
/// and minimal override calculation work identically everywhere.
class CurationDraft {
  CurationDraft({
    required this.mode,
    Set<String>? includedArtists,
    Set<String>? excludedArtists,
    Set<String>? includedAlbums,
    Set<String>? excludedAlbums,
    Set<String>? includedSongs,
    Set<String>? excludedSongs,
    Set<String>? includedPlaylists,
    Set<String>? excludedPlaylists,
    Map<String, String>? artistLabels,
  })  : includedArtists = includedArtists ?? <String>{},
        excludedArtists = excludedArtists ?? <String>{},
        includedAlbums = includedAlbums ?? <String>{},
        excludedAlbums = excludedAlbums ?? <String>{},
        includedSongs = includedSongs ?? <String>{},
        excludedSongs = excludedSongs ?? <String>{},
        includedPlaylists = includedPlaylists ?? <String>{},
        excludedPlaylists = excludedPlaylists ?? <String>{},
        artistLabels = artistLabels ?? <String, String>{};

  LibraryCurationMode mode;
  final Set<String> includedArtists;
  final Set<String> excludedArtists;
  final Set<String> includedAlbums;
  final Set<String> excludedAlbums;
  final Set<String> includedSongs;
  final Set<String> excludedSongs;
  final Set<String> includedPlaylists;
  final Set<String> excludedPlaylists;
  final Map<String, String> artistLabels;

  factory CurationDraft.fromCuration(UserLibraryCuration curation) {
    final filter = LibraryCurationFilter.fromCuration(curation);
    final labels = <String, String>{};
    for (final rule in curation.rules) {
      if (rule.targetType == CurationTargetType.artist &&
          rule.displayLabel != null &&
          rule.displayLabel!.trim().isNotEmpty) {
        labels[rule.normalizedTargetId] = rule.displayLabel!.trim();
      }
    }
    return CurationDraft(
      mode: curation.mode,
      includedArtists: Set<String>.from(filter.includedArtists),
      excludedArtists: Set<String>.from(filter.excludedArtists),
      includedAlbums: Set<String>.from(filter.includedAlbums),
      excludedAlbums: Set<String>.from(filter.excludedAlbums),
      includedSongs: Set<String>.from(filter.includedSongs),
      excludedSongs: Set<String>.from(filter.excludedSongs),
      includedPlaylists: Set<String>.from(filter.includedPlaylists),
      excludedPlaylists: Set<String>.from(filter.excludedPlaylists),
      artistLabels: labels,
    );
  }

  LibraryCurationFilter get filter => LibraryCurationFilter(
        mode: mode,
        includedArtists: Set<String>.unmodifiable(includedArtists),
        excludedArtists: Set<String>.unmodifiable(excludedArtists),
        includedAlbums: Set<String>.unmodifiable(includedAlbums),
        excludedAlbums: Set<String>.unmodifiable(excludedAlbums),
        includedSongs: Set<String>.unmodifiable(includedSongs),
        excludedSongs: Set<String>.unmodifiable(excludedSongs),
        includedPlaylists: Set<String>.unmodifiable(includedPlaylists),
        excludedPlaylists: Set<String>.unmodifiable(excludedPlaylists),
      );

  static List<CurationArtistGroup> buildArtistGroups({
    required List<CurationCatalogAlbum> albums,
    required List<CurationCatalogSong> standaloneSongs,
  }) {
    final displayByKey = <String, String>{};
    final albumsByKey = <String, Map<String, CurationCatalogAlbum>>{};
    final songsByKey = <String, Map<String, CurationCatalogSong>>{};

    for (final album in albums) {
      final credits = LibraryCurationFilter.splitArtists(album.artist);
      if (credits.isEmpty) continue;
      for (final credit in credits) {
        displayByKey.putIfAbsent(credit.key, () => credit.display);
        albumsByKey.putIfAbsent(credit.key, () => <String, CurationCatalogAlbum>{})[
            album.id] = album;
      }
    }

    for (final song in standaloneSongs) {
      if (song.albumId != null && song.albumId!.isNotEmpty) continue;
      final credits = LibraryCurationFilter.splitArtists(song.artist);
      if (credits.isEmpty) continue;
      for (final credit in credits) {
        displayByKey.putIfAbsent(credit.key, () => credit.display);
        songsByKey.putIfAbsent(credit.key, () => <String, CurationCatalogSong>{})[
            song.id] = song;
      }
    }

    final groups = <CurationArtistGroup>[];
    for (final entry in displayByKey.entries) {
      final key = entry.key;
      final artistAlbums = (albumsByKey[key]?.values.toList() ??
            <CurationCatalogAlbum>[])
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      final artistSongs = (songsByKey[key]?.values.toList() ??
            <CurationCatalogSong>[])
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      groups.add(CurationArtistGroup(
        key: key,
        displayName: entry.value,
        albums: artistAlbums,
        standaloneSongs: artistSongs,
      ));
    }

    groups.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return groups;
  }

  bool isArtistWholeEnabled(String artistKey) {
    if (mode == LibraryCurationMode.full) {
      return !excludedArtists.contains(artistKey);
    }
    return includedArtists.contains(artistKey);
  }

  int includedItemCountForArtist(CurationArtistGroup group) {
    final current = filter;
    var count = 0;
    for (final album in group.albums) {
      if (current.isAlbumIncluded(albumId: album.id, artist: album.artist)) {
        count++;
      }
    }
    for (final song in group.standaloneSongs) {
      if (current.isSongIncluded(
        songId: song.id,
        artist: song.artist,
        albumId: song.albumId,
      )) {
        count++;
      }
    }
    return count;
  }

  CurationArtistSelectionState artistCheckboxState(CurationArtistGroup group) {
    final total = group.totalItems;
    if (total == 0) {
      return isArtistWholeEnabled(group.key)
          ? CurationArtistSelectionState.all
          : CurationArtistSelectionState.none;
    }
    final included = includedItemCountForArtist(group);
    if (included == 0) return CurationArtistSelectionState.none;
    if (included == total && isArtistWholeEnabled(group.key)) {
      return CurationArtistSelectionState.all;
    }
    if (included == total && mode == LibraryCurationMode.full) {
      return CurationArtistSelectionState.all;
    }
    return CurationArtistSelectionState.partial;
  }

  void setArtistAllToggle(CurationArtistGroup group, bool includeAll) {
    artistLabels[group.key] = group.displayName;
    if (includeAll) {
      excludedArtists.remove(group.key);
      if (mode == LibraryCurationMode.curated) {
        includedArtists.add(group.key);
      }
      for (final album in group.albums) {
        excludedAlbums.remove(album.id);
      }
      for (final song in group.standaloneSongs) {
        excludedSongs.remove(song.id);
      }
    } else {
      includedArtists.remove(group.key);
      if (mode == LibraryCurationMode.full) {
        excludedArtists.add(group.key);
      }
      for (final album in group.albums) {
        includedAlbums.remove(album.id);
      }
      for (final song in group.standaloneSongs) {
        includedSongs.remove(song.id);
      }
    }
  }

  void toggleArtistWhole(CurationArtistGroup group) {
    final state = artistCheckboxState(group);
    final enableAll = state != CurationArtistSelectionState.all;
    artistLabels[group.key] = group.displayName;
    if (enableAll) {
      excludedArtists.remove(group.key);
      if (mode == LibraryCurationMode.curated) {
        includedArtists.add(group.key);
      }
      for (final album in group.albums) {
        excludedAlbums.remove(album.id);
        includedAlbums.remove(album.id);
      }
      for (final song in group.standaloneSongs) {
        excludedSongs.remove(song.id);
        includedSongs.remove(song.id);
      }
    } else {
      includedArtists.remove(group.key);
      if (mode == LibraryCurationMode.full) {
        excludedArtists.add(group.key);
      }
      for (final album in group.albums) {
        includedAlbums.remove(album.id);
        excludedAlbums.remove(album.id);
      }
      for (final song in group.standaloneSongs) {
        includedSongs.remove(song.id);
        excludedSongs.remove(song.id);
      }
    }
  }

  void toggleAlbum(CurationCatalogAlbum album) {
    final current = filter;
    final wantIncluded =
        !current.isAlbumIncluded(albumId: album.id, artist: album.artist);
    final keys = LibraryCurationFilter.artistKeysFor(album.artist);
    final artistExcluded = keys.any(excludedArtists.contains);
    final artistIncluded = keys.any(includedArtists.contains);

    if (wantIncluded) {
      excludedAlbums.remove(album.id);
      final includedByDefault =
          (mode == LibraryCurationMode.full && !artistExcluded) ||
              (mode == LibraryCurationMode.curated &&
                  artistIncluded &&
                  !artistExcluded);
      if (includedByDefault) {
        includedAlbums.remove(album.id);
      } else {
        includedAlbums.add(album.id);
      }
    } else {
      includedAlbums.remove(album.id);
      final excludedByDefault =
          (mode == LibraryCurationMode.curated && !artistIncluded) ||
              artistExcluded;
      if (excludedByDefault) {
        excludedAlbums.remove(album.id);
      } else {
        excludedAlbums.add(album.id);
      }
    }
  }

  void toggleSong(CurationCatalogSong song, {String? albumArtist}) {
    final current = filter;
    final wantIncluded = !current.isSongIncluded(
      songId: song.id,
      artist: song.artist,
      albumId: song.albumId,
      albumArtist: albumArtist,
    );

    if (wantIncluded) {
      excludedSongs.remove(song.id);
      final withoutRule = LibraryCurationFilter(
        mode: mode,
        includedArtists: includedArtists,
        excludedArtists: excludedArtists,
        includedAlbums: includedAlbums,
        excludedAlbums: excludedAlbums,
        includedSongs: includedSongs.difference(<String>{song.id}),
        excludedSongs: excludedSongs,
        includedPlaylists: includedPlaylists,
        excludedPlaylists: excludedPlaylists,
      );
      if (withoutRule.isSongIncluded(
        songId: song.id,
        artist: song.artist,
        albumId: song.albumId,
        albumArtist: albumArtist,
      )) {
        includedSongs.remove(song.id);
      } else {
        includedSongs.add(song.id);
      }
    } else {
      includedSongs.remove(song.id);
      final withoutRule = LibraryCurationFilter(
        mode: mode,
        includedArtists: includedArtists,
        excludedArtists: excludedArtists,
        includedAlbums: includedAlbums,
        excludedAlbums: excludedAlbums,
        includedSongs: includedSongs,
        excludedSongs: excludedSongs.difference(<String>{song.id}),
        includedPlaylists: includedPlaylists,
        excludedPlaylists: excludedPlaylists,
      );
      if (!withoutRule.isSongIncluded(
        songId: song.id,
        artist: song.artist,
        albumId: song.albumId,
        albumArtist: albumArtist,
      )) {
        excludedSongs.remove(song.id);
      } else {
        excludedSongs.add(song.id);
      }
    }
  }

  void togglePlaylist(String playlistId) {
    final wantIncluded = !filter.isServerPlaylistIncluded(playlistId);
    if (wantIncluded) {
      excludedPlaylists.remove(playlistId);
      if (mode == LibraryCurationMode.curated) {
        includedPlaylists.add(playlistId);
      }
    } else {
      includedPlaylists.remove(playlistId);
      if (mode == LibraryCurationMode.full) {
        excludedPlaylists.add(playlistId);
      }
    }
  }

  void selectAll() {
    mode = LibraryCurationMode.full;
    _clearAllSets();
  }

  void clearAll() {
    mode = LibraryCurationMode.curated;
    _clearAllSets();
  }

  void _clearAllSets() {
    includedArtists.clear();
    excludedArtists.clear();
    includedAlbums.clear();
    excludedAlbums.clear();
    includedSongs.clear();
    excludedSongs.clear();
    includedPlaylists.clear();
    excludedPlaylists.clear();
  }

  List<CurationRuleEntry> toRules() {
    final now = DateTime.now().toUtc();
    final rules = <CurationRuleEntry>[];
    void addSet(
      Set<String> ids,
      CurationTargetType type,
      CurationRuleAction action,
    ) {
      for (final id in ids) {
        rules.add(CurationRuleEntry(
          targetType: type,
          targetId: id,
          action: action,
          updatedAt: now,
          displayLabel: type == CurationTargetType.artist ? artistLabels[id] : null,
        ));
      }
    }

    addSet(includedArtists, CurationTargetType.artist, CurationRuleAction.include);
    addSet(excludedArtists, CurationTargetType.artist, CurationRuleAction.exclude);
    addSet(includedAlbums, CurationTargetType.album, CurationRuleAction.include);
    addSet(excludedAlbums, CurationTargetType.album, CurationRuleAction.exclude);
    addSet(includedSongs, CurationTargetType.song, CurationRuleAction.include);
    addSet(excludedSongs, CurationTargetType.song, CurationRuleAction.exclude);
    addSet(includedPlaylists, CurationTargetType.playlist, CurationRuleAction.include);
    addSet(excludedPlaylists, CurationTargetType.playlist, CurationRuleAction.exclude);
    return rules;
  }
}
