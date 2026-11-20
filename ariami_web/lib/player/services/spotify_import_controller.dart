import 'package:ariami_core/models/listening_stats_models.dart'
    show ListeningEvent;
import 'package:ariami_core/services/stats/spotify_import/library_track_matcher.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_import_models.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_importer.dart';
import 'package:flutter/foundation.dart';

import '../models/player_models.dart';
import 'player_api_client.dart';
import 'player_host.dart';

enum SpotifyImportPhase {
  idle,
  reading,
  matching,
  preview,
  uploading,
  done,
  error,
}

/// A user-facing import failure with a message safe to show in the UI.
class SpotifyImportException implements Exception {
  final String message;

  const SpotifyImportException(this.message);

  @override
  String toString() => message;
}

/// Orchestrates the Spotify Extended Streaming History import: pick the
/// export folder, feed the records to the core [SpotifyImporter], preview the
/// outcome, then upload the events in server-sized chunks. Parsing, matching
/// and event-id logic lives in ariami_core and runs in a background isolate;
/// this controller only drives it.
class SpotifyImportController extends ChangeNotifier {
  /// The server caps one events POST at 500 events.
  static const int uploadBatchSize = 500;

  SpotifyImportController({
    bool supportsListeningSourceReset = false,
    SpotifyExportPicker? picker,
    String clientKind = 'web',
  })  : _supportsListeningSourceReset = supportsListeningSourceReset,
        _picker = picker,
        _clientKind = clientKind;

  /// Fail-closed: undo is refused unless the server explicitly advertised
  /// the Spotify-import-only reset endpoint.
  final bool _supportsListeningSourceReset;
  final SpotifyExportPicker? _picker;
  final String _clientKind;

  SpotifyImportPhase _phase = SpotifyImportPhase.idle;
  String _statusMessage = '';
  SpotifyImportResult? _result;
  String? _analysisAccountUserId;

  int _uploadedCount = 0;
  int _totalCount = 0;
  int _acceptedCount = 0;
  int _duplicatesCount = 0;
  int _rejectedCount = 0;

  bool _undoing = false;
  int? _undoDeletedCount;

  SpotifyImportPhase get phase => _phase;
  String get statusMessage => _statusMessage;
  SpotifyImportResult? get result => _result;

  int get uploadedCount => _uploadedCount;

  int get totalCount => _totalCount;

  int get acceptedCount => _acceptedCount;

  /// Plays the server already had (dedup by eventId) across all sent batches.
  int get duplicatesCount => _duplicatesCount;

  int get rejectedCount => _rejectedCount;

  bool get undoInProgress => _undoing;

  int? get undoDeletedCount => _undoDeletedCount;

  static LibraryCatalogEntry catalogEntryForTrack(Track track) {
    return LibraryCatalogEntry(
      songId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.albumTitle,
      albumId: track.albumId,
      durationMs: track.durationSeconds * 1000,
    );
  }

  /// The listener's local UTC offset in minutes at [utcMillis]. Dart's local
  /// `timeZoneOffset` is historically accurate per instant (DST-aware), so no
  /// timezone database is needed.
  static int localTzOffsetMinutes(int utcMillis) =>
      DateTime.fromMillisecondsSinceEpoch(utcMillis, isUtc: false)
          .timeZoneOffset
          .inMinutes;

  /// Lets the user pick their Spotify history files via the configured
  /// [SpotifyExportPicker] and analyzes the combined records.
  Future<void> pickAndAnalyze(
    List<Track> librarySongs,
    String accountUserId,
  ) async {
    if (_phase == SpotifyImportPhase.reading ||
        _phase == SpotifyImportPhase.matching ||
        _phase == SpotifyImportPhase.uploading) {
      return;
    }
    final picker = _picker;
    if (picker == null) {
      _setPhase(
        SpotifyImportPhase.error,
        'Spotify import is unavailable on this platform.',
      );
      return;
    }
    _setPhase(SpotifyImportPhase.reading, 'Reading Spotify export…');
    try {
      final records = await picker.pickAndReadRecords();
      if (records == null) {
        _setPhase(SpotifyImportPhase.idle, '');
        return;
      }
      if (records.isEmpty) {
        throw const SpotifyImportException(
          'The selected Spotify history files are empty.',
        );
      }
      await analyzeRecords(records, librarySongs, accountUserId);
    } on SpotifyImportException catch (e) {
      _setPhase(SpotifyImportPhase.error, e.message);
    } catch (_) {
      _setPhase(
        SpotifyImportPhase.error,
        'Could not read the Spotify export. Make sure you picked your '
        'Streaming_History_Audio_*.json files.',
      );
    }
  }

  /// Parses, matches and builds events for already-decoded [records] via the
  /// core importer, landing on the preview phase. Kept separate from the
  /// picker/file IO so tests can drive it directly.
  Future<void> analyzeRecords(
    List<Map<String, dynamic>> records,
    List<Track> librarySongs,
    String accountUserId,
  ) async {
    _result = null;
    _analysisAccountUserId = null;
    _setPhase(
      SpotifyImportPhase.matching,
      'Matching plays against your library…',
    );
    try {
      final catalog = <LibraryCatalogEntry>[
        for (final track in librarySongs) catalogEntryForTrack(track),
      ];
      // Indexes are built once, then every unique track key matches in O(1).
      final result = await compute(
        _runSpotifyImport,
        _SpotifyImportWork(
          records: records,
          catalog: catalog,
          userId: accountUserId,
          clientKind: _clientKind,
        ),
        debugLabel: 'Spotify import matching',
      );
      _result = result;
      _analysisAccountUserId = accountUserId;
      _totalCount = result.events.length;
      _setPhase(SpotifyImportPhase.preview, '');
    } catch (_) {
      _setPhase(
        SpotifyImportPhase.error,
        'Could not analyze the Spotify export.',
      );
    }
  }

  /// Unique library tracks matched vs unique Spotify tracks that matched
  /// nothing in the last analysis (unmatched plays carry `spotify-uri:` song
  /// ids). Zeroed before any analysis.
  (int matched, int unmatched) get matchedTrackCounts {
    final events = _result?.events;
    if (events == null) return (0, 0);
    final matched = <String>{};
    final unmatched = <String>{};
    for (final event in events) {
      (event.songId.startsWith('spotify-uri:') ? unmatched : matched)
          .add(event.songId);
    }
    return (matched.length, unmatched.length);
  }

  /// Uploads the analyzed events. Each batch is idempotent server-side
  /// (dedup by eventId), so an interrupted upload can simply be retried.
  Future<void> confirmUpload(PlayerApiClient api) async {
    final result = _result;
    final accountUserId = _analysisAccountUserId;
    if (result == null ||
        accountUserId == null ||
        _phase == SpotifyImportPhase.uploading) {
      return;
    }
    if (!await _isExpectedAccount(api, accountUserId)) return;
    await uploadEvents(api, result.events);
  }

  /// Chunks [events] into ≤[uploadBatchSize] batches and POSTs them
  /// sequentially, exposing per-batch progress. On a batch failure the phase
  /// flips to error naming the failed chunk; already-sent batches are durable.
  Future<void> uploadEvents(
    PlayerApiClient api,
    List<ListeningEvent> events,
  ) async {
    _uploadedCount = 0;
    _acceptedCount = 0;
    _duplicatesCount = 0;
    _rejectedCount = 0;
    _totalCount = events.length;
    _setPhase(SpotifyImportPhase.uploading, 'Uploading plays…');
    var chunkIndex = 0;
    try {
      for (var i = 0; i < events.length; i += uploadBatchSize) {
        chunkIndex++;
        final end = i + uploadBatchSize > events.length
            ? events.length
            : i + uploadBatchSize;
        final chunk = <Map<String, dynamic>>[
          for (final event in events.sublist(i, end)) event.toJson(),
        ];
        final response = await api.postListeningEvents(chunk);
        _acceptedCount += response['accepted'] as int? ?? 0;
        _duplicatesCount += response['duplicates'] as int? ?? 0;
        _rejectedCount += response['rejected'] as int? ?? 0;
        _uploadedCount += chunk.length;
        notifyListeners();
      }
      _setPhase(SpotifyImportPhase.done, '');
    } catch (error) {
      if (error is PlayerApiException && error.statusCode == 404) {
        // The import endpoint does not exist on this server yet — this is
        // endpoint compatibility, not selective-reset capability gating.
        _setPhase(
          SpotifyImportPhase.error,
          'Your server must be updated before it can accept Spotify imports.',
        );
        return;
      }
      _setPhase(
        SpotifyImportPhase.error,
        'Upload failed on batch $chunkIndex. Plays already uploaded are '
        'saved — retry to continue.',
      );
    }
  }

  /// Deletes every Spotify-imported play for this account, exposing how many
  /// events were removed through [undoDeletedCount].
  Future<void> undo(
    PlayerApiClient api, {
    required String accountUserId,
  }) async {
    if (!_supportsListeningSourceReset) {
      _setPhase(
        SpotifyImportPhase.error,
        'Your server must be updated before a Spotify import can be safely '
        'removed.',
      );
      return;
    }
    if (_undoing) return;
    _undoing = true;
    _undoDeletedCount = null;
    notifyListeners();
    try {
      final supported = await api.supportsListeningSourceResetNow();
      if (!supported) {
        _setPhase(
          SpotifyImportPhase.error,
          'Your server must be updated before a Spotify import can be safely '
          'removed.',
        );
        return;
      }
      if (!await _isExpectedAccount(api, accountUserId)) return;
      _undoDeletedCount = await api.postSpotifyImportReset();
    } catch (_) {
      _setPhase(
        SpotifyImportPhase.error,
        'Could not remove the Spotify import. Please try again.',
      );
    } finally {
      _undoing = false;
      notifyListeners();
    }
  }

  void reset() {
    _phase = SpotifyImportPhase.idle;
    _statusMessage = '';
    _result = null;
    _analysisAccountUserId = null;
    _uploadedCount = 0;
    _totalCount = 0;
    _acceptedCount = 0;
    _duplicatesCount = 0;
    _rejectedCount = 0;
    _undoDeletedCount = null;
    notifyListeners();
  }

  /// Destructive and import operations are tied to the account that opened
  /// the flow. Fail closed if the session changed or cannot be revalidated.
  Future<bool> _isExpectedAccount(
    PlayerApiClient api,
    String expectedUsername,
  ) async {
    try {
      final currentUsername = (await api.fetchMe()).username.trim();
      if (currentUsername == expectedUsername.trim() &&
          currentUsername.isNotEmpty) {
        return true;
      }
    } catch (_) {
      // The user-facing refusal below is intentionally the same for an
      // unreachable server and a changed/expired session.
    }
    _setPhase(
      SpotifyImportPhase.error,
      'The signed-in account could not be confirmed. Start the Spotify '
      'import again after reconnecting.',
    );
    return false;
  }

  void _setPhase(SpotifyImportPhase phase, String message) {
    _phase = phase;
    _statusMessage = message;
    notifyListeners();
  }
}

class _SpotifyImportWork {
  const _SpotifyImportWork({
    required this.records,
    required this.catalog,
    required this.userId,
    required this.clientKind,
  });

  final List<Map<String, dynamic>> records;
  final List<LibraryCatalogEntry> catalog;
  final String userId;
  final String clientKind;
}

/// Top-level entry point required by [compute]. Keeping the entire pure Core
/// pipeline here prevents catalog indexing, parsing, matching and event
/// construction from blocking Flutter's UI isolate.
Future<SpotifyImportResult> _runSpotifyImport(_SpotifyImportWork work) {
  return const SpotifyImporter().run(
    records: work.records,
    matcher: LibraryTrackMatcher(work.catalog),
    tzOffsetMinutesFor: SpotifyImportController.localTzOffsetMinutes,
    userId: work.userId,
    clientKind: work.clientKind,
  );
}
