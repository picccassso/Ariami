import 'package:path/path.dart' as path;

import 'package:ariami_core/models/playlist_suggestion.dart';
import 'package:ariami_core/models/scan_diagnostics.dart';
import 'package:ariami_core/models/song_metadata.dart';

/// Result of classifying unmarked folders.
///
/// [autoImports] are high-confidence playlist folders the scanner imports
/// automatically (they become real playlists, exactly like `[PLAYLIST]`
/// folders). [suggestions] are medium-confidence folders that stay advisory —
/// surfaced in scan diagnostics for the user to approve or ignore. Both lists
/// are path-sorted and disjoint.
class PlaylistFolderClassification {
  const PlaylistFolderClassification({
    this.autoImports = const [],
    this.suggestions = const [],
  });

  /// High-confidence playlist folders, imported automatically.
  final List<PlaylistSuggestion> autoImports;

  /// Medium-confidence folders, advisory only.
  final List<PlaylistSuggestion> suggestions;
}

/// "This folder looks like a playlist" detection for unmarked folders.
///
/// Explicit `[PLAYLIST]` folders and `.m3u`/`.m3u8` files always import.
/// On top of those, folders with *strong* playlist evidence auto-import
/// (so a fresh install detects normal mixed-song folders without the user
/// knowing about `[PLAYLIST]`), and folders with medium evidence surface as
/// advisory suggestions. Album-shaped folders are never touched.
/// See PLAYLIST_DETECTION.md.
///
/// Rules summary:
/// - Only folders that directly contain loose audio files are considered
///   (nested album subfolders are their own folders): at least
///   [minSongsForSuggestion] files to be suggested, at least
///   [minSongsForAutoImport] to auto-import.
/// - The scan root, anything inside an explicit playlist folder, and
///   user-ignored folders are never classified.
/// - Album-shaped folders are never touched: a dominant shared album tag,
///   only one or two distinct albums, one dominant album artist, or any
///   "Various Artists"-style compilation tagging all disqualify a folder.
/// - A *suggestion* requires tag-diversity evidence (many distinct albums or
///   many distinct artists) plus at least one more signal (the other
///   diversity signal, missing/inconsistent track numbers, or a
///   playlist-like folder name). A name alone is never enough.
/// - An *auto-import* additionally requires both diversity signals (many
///   albums AND many artists, no dominant album), plus either a
///   playlist-like folder name or very high artist/album diversity.
/// - If most tracks are missing album tags there is no diversity evidence:
///   a playlist-like name plus [minSongsForAutoImport] files still
///   auto-imports (untagged dumps named "Gym Mix" are playlists, and their
///   tracks would stay standalone anyway), a playlist-like name with fewer
///   files is only suggested, flagged with `missingTags: true`.
class PlaylistFolderClassifier {
  const PlaylistFolderClassifier();

  /// Minimum loose audio files a folder needs before it can be suggested.
  static const int minSongsForSuggestion = 5;

  /// Minimum loose audio files a folder needs before it can auto-import.
  static const int minSongsForAutoImport = 8;

  /// A single album tag covering at least this fraction of tagged tracks
  /// marks the folder as album-shaped.
  static const double dominantAlbumFractionCutoff = 0.6;

  /// A single album artist covering at least this fraction of tagged tracks
  /// marks the folder as an artist/album dump, not a playlist.
  static const double dominantAlbumArtistFractionCutoff = 0.8;

  /// Minimum fraction of tracks with an album tag for tag-based signals to
  /// be trusted.
  static const double minTaggedFraction = 0.5;

  /// "Very high diversity" — enough to auto-import without a playlist-like
  /// name: at least this many distinct albums AND artists...
  static const int autoImportMinAlbums = 6;
  static const int autoImportMinArtists = 6;

  /// ...with no album above this share of tagged tracks...
  static const double autoImportDominantAlbumCutoff = 0.3;

  /// ...and no artist above this share of tagged tracks.
  static const double autoImportDominantArtistCutoff = 0.4;

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

  /// Classifies unmarked folders among [songs] into auto-imports and
  /// suggestions.
  ///
  /// [libraryRootPath] is never classified itself. Folders inside any of
  /// [explicitPlaylistFolderPaths] are skipped — they are already playlists
  /// (this includes user-approved suggestion folders, which scan as explicit
  /// sources). Folders in [ignoredFolderPaths] (normalized) are skipped —
  /// the user asked to never import or suggest them.
  ///
  /// Nested auto-imports collapse into the outermost folder (mirroring
  /// `[PLAYLIST]` nesting), and a suggestion inside an auto-imported folder
  /// is dropped — its files already belong to the imported playlist. Both
  /// lists are path-sorted; suggestions are capped at
  /// [ScanDiagnostics.maxPlaylistSuggestions] for determinism.
  PlaylistFolderClassification classify({
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

    final autoImports = <PlaylistSuggestion>[];
    final suggestions = <PlaylistSuggestion>[];
    for (final entry in songsByFolder.entries) {
      final folderPath = entry.key;
      if (path.normalize(folderPath) == normalizedRoot) continue;
      if (ignoredFolderPaths.contains(path.normalize(folderPath))) continue;
      if (_isInsideAny(folderPath, explicitPlaylistFolderPaths)) continue;

      final classified = _classifyFolder(folderPath, entry.value);
      if (classified == null) continue;
      (classified.autoImport ? autoImports : suggestions)
          .add(classified.suggestion);
    }

    autoImports.sort((a, b) => a.folderPath.compareTo(b.folderPath));
    suggestions.sort((a, b) => a.folderPath.compareTo(b.folderPath));

    // Collapse nested auto-imports into the outermost folder (path order
    // guarantees parents come first) and drop suggestions living inside an
    // auto-imported folder — their files join that playlist anyway.
    final keptAutoImportPaths = <String>{};
    final keptAutoImports = <PlaylistSuggestion>[];
    for (final autoImport in autoImports) {
      if (_isInsideAny(autoImport.folderPath, keptAutoImportPaths)) continue;
      keptAutoImportPaths.add(autoImport.folderPath);
      keptAutoImports.add(autoImport);
    }
    var keptSuggestions = suggestions
        .where((s) => !_isInsideAny(s.folderPath, keptAutoImportPaths))
        .toList();

    if (keptSuggestions.length > ScanDiagnostics.maxPlaylistSuggestions) {
      keptSuggestions =
          keptSuggestions.sublist(0, ScanDiagnostics.maxPlaylistSuggestions);
    }
    return PlaylistFolderClassification(
      autoImports: keptAutoImports,
      suggestions: keptSuggestions,
    );
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

  ({PlaylistSuggestion suggestion, bool autoImport})? _classifyFolder(
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
    // reliable diversity evidence, so only a playlist-like name surfaces the
    // folder. With enough files it still auto-imports (an untagged "Gym Mix"
    // dump is a playlist, and its tracks stay standalone either way);
    // smaller folders are suggested and flagged for manual review.
    if (taggedFraction < minTaggedFraction) {
      if (!nameIsPlaylistLike) return null;
      final autoImport = folderSongs.length >= minSongsForAutoImport &&
          !hasCompilationTag;
      return (
        suggestion: PlaylistSuggestion(
          folderPath: folderPath,
          name: folderName,
          songCount: folderSongs.length,
          artistCount: artistCounts.length,
          albumCount: albumCounts.length,
          missingTags: true,
          reasons: [
            'folder name looks like a playlist',
            if (autoImport)
              'most tracks are missing tags'
            else
              'most tracks are missing tags — review before importing',
          ],
        ),
        autoImport: autoImport,
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

    // Auto-import needs strong evidence: enough files, both diversity
    // signals (several distinct albums AND artists, no dominant album), and
    // either a playlist-like name or very high diversity on its own.
    final veryHighDiversity = albumCounts.length >= autoImportMinAlbums &&
        artistCounts.length >= autoImportMinArtists &&
        dominantAlbumFraction <= autoImportDominantAlbumCutoff &&
        dominantArtistFraction <= autoImportDominantArtistCutoff;
    final autoImport = folderSongs.length >= minSongsForAutoImport &&
        manyAlbums &&
        manyArtists &&
        (nameIsPlaylistLike || veryHighDiversity);

    return (
      suggestion: PlaylistSuggestion(
        folderPath: folderPath,
        name: folderName,
        songCount: folderSongs.length,
        artistCount: artistCounts.length,
        albumCount: albumCounts.length,
        reasons: reasons,
      ),
      autoImport: autoImport,
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
