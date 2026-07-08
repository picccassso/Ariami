import 'package:path/path.dart' as path;

import 'package:ariami_core/models/playlist_suggestion.dart';
import 'package:ariami_core/models/scan_diagnostics.dart';
import 'package:ariami_core/models/song_metadata.dart';

/// Conservative "this folder looks like a playlist" detection.
///
/// Produces advisory [PlaylistSuggestion]s only — nothing here creates a
/// playlist. Explicit `[PLAYLIST]` folders and `.m3u`/`.m3u8` files remain
/// the only automatic playlist sources. See PLAYLIST_DETECTION.md.
///
/// Rules summary:
/// - Only folders that directly contain at least [minSongsForSuggestion]
///   loose audio files are considered (nested album subfolders are their
///   own folders).
/// - The scan root and anything inside an explicit playlist folder are
///   never suggested.
/// - Album-shaped folders are never suggested: a dominant shared album tag,
///   only one or two distinct albums, one dominant album artist, or any
///   "Various Artists"-style compilation tagging all disqualify a folder.
/// - A suggestion requires tag-diversity evidence (many distinct albums or
///   many distinct artists) plus at least one more signal (the other
///   diversity signal, missing/inconsistent track numbers, or a
///   playlist-like folder name). A name alone is never enough.
/// - If most tracks are missing album tags, the folder is only surfaced
///   when its name is playlist-like, flagged with `missingTags: true` so
///   users review it before importing.
class PlaylistFolderClassifier {
  const PlaylistFolderClassifier();

  /// Minimum loose audio files a folder needs before it can be suggested.
  static const int minSongsForSuggestion = 5;

  /// A single album tag covering at least this fraction of tagged tracks
  /// marks the folder as album-shaped.
  static const double dominantAlbumFractionCutoff = 0.6;

  /// A single album artist covering at least this fraction of tagged tracks
  /// marks the folder as an artist/album dump, not a playlist.
  static const double dominantAlbumArtistFractionCutoff = 0.8;

  /// Minimum fraction of tracks with an album tag for tag-based signals to
  /// be trusted.
  static const double minTaggedFraction = 0.5;

  /// Words that make a folder name "playlist-like" (matched on word
  /// boundaries, case-insensitive).
  static const List<String> playlistNameWords = [
    'playlist',
    'mix',
    'mixtape',
    'favourites',
    'favorites',
    'liked',
    'road trip',
    'roadtrip',
    'gym',
    'workout',
    'running',
    'party',
    'setlist',
    'car',
  ];

  /// Detects likely-playlist folders among [songs].
  ///
  /// [libraryRootPath] is never suggested itself. Folders inside any of
  /// [explicitPlaylistFolderPaths] are skipped — they are already playlists
  /// (this includes user-approved suggestion folders, which scan as explicit
  /// sources). Folders in [ignoredFolderPaths] (normalized) are skipped —
  /// the user asked to never see them again. Results are path-sorted and
  /// capped at [ScanDiagnostics.maxPlaylistSuggestions] for determinism.
  List<PlaylistSuggestion> detectSuggestions({
    required List<SongMetadata> songs,
    required String libraryRootPath,
    Set<String> explicitPlaylistFolderPaths = const {},
    Set<String> ignoredFolderPaths = const {},
  }) {
    final normalizedRoot = path.normalize(libraryRootPath);

    final songsByFolder = <String, List<SongMetadata>>{};
    for (final song in songs) {
      songsByFolder
          .putIfAbsent(path.dirname(song.filePath), () => [])
          .add(song);
    }

    final suggestions = <PlaylistSuggestion>[];
    for (final entry in songsByFolder.entries) {
      final folderPath = entry.key;
      if (path.normalize(folderPath) == normalizedRoot) continue;
      if (ignoredFolderPaths.contains(path.normalize(folderPath))) continue;
      if (_isInsideAny(folderPath, explicitPlaylistFolderPaths)) continue;

      final suggestion = _classifyFolder(folderPath, entry.value);
      if (suggestion != null) {
        suggestions.add(suggestion);
      }
    }

    suggestions.sort((a, b) => a.folderPath.compareTo(b.folderPath));
    if (suggestions.length > ScanDiagnostics.maxPlaylistSuggestions) {
      return suggestions.sublist(0, ScanDiagnostics.maxPlaylistSuggestions);
    }
    return suggestions;
  }

  bool _isInsideAny(String folderPath, Set<String> ancestors) {
    for (final ancestor in ancestors) {
      if (folderPath == ancestor ||
          folderPath.startsWith('$ancestor${path.separator}')) {
        return true;
      }
    }
    return false;
  }

  PlaylistSuggestion? _classifyFolder(
    String folderPath,
    List<SongMetadata> folderSongs,
  ) {
    if (folderSongs.length < minSongsForSuggestion) return null;

    final folderName = path.basename(folderPath);
    final nameIsPlaylistLike = _hasPlaylistLikeName(folderName);

    String? cleanTag(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    final taggedSongs = folderSongs
        .where((song) => cleanTag(song.album) != null)
        .toList(growable: false);
    final taggedFraction = taggedSongs.length / folderSongs.length;

    final albumCounts = <String, int>{};
    final artistCounts = <String, int>{};
    final albumArtistCounts = <String, int>{};
    var hasCompilationTag = false;
    for (final song in taggedSongs) {
      final album = cleanTag(song.album)!.toLowerCase();
      albumCounts[album] = (albumCounts[album] ?? 0) + 1;

      final albumArtist = cleanTag(song.albumArtist)?.toLowerCase();
      if (albumArtist != null) {
        albumArtistCounts[albumArtist] =
            (albumArtistCounts[albumArtist] ?? 0) + 1;
        if (albumArtist.contains('various')) hasCompilationTag = true;
      }

      final artist = (albumArtist ?? cleanTag(song.artist)?.toLowerCase());
      if (artist != null) {
        artistCounts[artist] = (artistCounts[artist] ?? 0) + 1;
      }
    }

    // Missing-tag branch: without album tags on most tracks there is no
    // reliable diversity evidence. Only a playlist-like name surfaces the
    // folder, and it is explicitly flagged for manual review.
    if (taggedFraction < minTaggedFraction) {
      if (!nameIsPlaylistLike) return null;
      return PlaylistSuggestion(
        folderPath: folderPath,
        name: folderName,
        songCount: folderSongs.length,
        artistCount: artistCounts.length,
        albumCount: albumCounts.length,
        missingTags: true,
        reasons: const [
          'folder name looks like a playlist',
          'most tracks are missing tags — review before importing',
        ],
      );
    }

    // Album-shape guards — any of these means "leave the folder alone".
    if (hasCompilationTag) return null;
    if (albumCounts.length <= 2) return null;

    int maxCount(Map<String, int> counts) =>
        counts.values.fold(0, (a, b) => a > b ? a : b);

    final dominantAlbumFraction = maxCount(albumCounts) / taggedSongs.length;
    if (dominantAlbumFraction >= dominantAlbumFractionCutoff) return null;

    if (albumArtistCounts.isNotEmpty &&
        maxCount(albumArtistCounts) / taggedSongs.length >=
            dominantAlbumArtistFractionCutoff) {
      return null;
    }

    // Positive playlist signals.
    final reasons = <String>[];

    final manyAlbums =
        albumCounts.length >= 4 && dominantAlbumFraction <= 0.4;
    if (manyAlbums) {
      reasons.add('tracks come from ${albumCounts.length} different albums');
    }

    final dominantArtistFraction = artistCounts.isEmpty
        ? 0.0
        : maxCount(artistCounts) / taggedSongs.length;
    final manyArtists =
        artistCounts.length >= 4 && dominantArtistFraction <= 0.5;
    if (manyArtists) {
      reasons.add('tracks come from ${artistCounts.length} different artists');
    }

    // Track numbers: playlists collected from many albums keep their
    // original numbering (duplicates/gaps) or lose it entirely.
    final trackNumbers = folderSongs
        .map((song) => song.trackNumber)
        .whereType<int>()
        .toList(growable: false);
    final trackNumberFraction = trackNumbers.length / folderSongs.length;
    final duplicatedTrackNumbers =
        trackNumbers.toSet().length < trackNumbers.length;
    final inconsistentTrackNumbers =
        trackNumberFraction < 0.5 || duplicatedTrackNumbers;
    if (inconsistentTrackNumbers) {
      reasons.add('track numbers are missing or inconsistent');
    }

    if (nameIsPlaylistLike) {
      reasons.add('folder name looks like a playlist');
    }

    // Require tag-diversity evidence plus at least one supporting signal.
    // A playlist-like name alone (or name + track numbers) is never enough.
    final diversitySignals = (manyAlbums ? 1 : 0) + (manyArtists ? 1 : 0);
    final totalSignals = diversitySignals +
        (inconsistentTrackNumbers ? 1 : 0) +
        (nameIsPlaylistLike ? 1 : 0);
    if (diversitySignals == 0 || totalSignals < 2) return null;

    return PlaylistSuggestion(
      folderPath: folderPath,
      name: folderName,
      songCount: folderSongs.length,
      artistCount: artistCounts.length,
      albumCount: albumCounts.length,
      reasons: reasons,
    );
  }

  bool _hasPlaylistLikeName(String folderName) {
    final normalized = folderName.toLowerCase();
    for (final word in playlistNameWords) {
      final pattern = RegExp('(^|[^a-z0-9])${RegExp.escape(word)}'
          r'($|[^a-z0-9])');
      if (pattern.hasMatch(normalized)) return true;
    }
    return false;
  }
}
