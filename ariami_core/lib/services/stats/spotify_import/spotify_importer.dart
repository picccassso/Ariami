import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_event_builder.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_history_parser.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_import_models.dart';

/// The outcome of one import run: the events to upload (chunked at the
/// server's 500-events-per-POST cap, by the caller), the parse accounting,
/// and how well the library matching went.
class SpotifyImportResult {
  final List<ListeningEvent> events;
  final SpotifyParseSummary summary;

  /// Unique matched tracks / unique tracks seen (0.0..1.0).
  final double trackMatchRate;

  /// Matched plays / eligible plays (0.0..1.0).
  final double playMatchRate;

  const SpotifyImportResult({
    required this.events,
    required this.summary,
    required this.trackMatchRate,
    required this.playMatchRate,
  });
}

/// Thin facade tying the pipeline together: parse → match → build events.
class SpotifyImporter {
  const SpotifyImporter({
    SpotifyHistoryParser parser = const SpotifyHistoryParser(),
    SpotifyEventBuilder builder = const SpotifyEventBuilder(),
  })  : _parser = parser,
        _builder = builder;

  final SpotifyHistoryParser _parser;
  final SpotifyEventBuilder _builder;

  Future<SpotifyImportResult> run({
    required List<Map<String, dynamic>> records,
    required TrackMatcher matcher,
    required TzOffsetMinutesFor tzOffsetMinutesFor,
    required String userId,
    required String clientKind,
    bool importIncognito = false,
  }) async {
    final parsed = _parser.parse(
      records,
      tzOffsetMinutesFor: tzOffsetMinutesFor,
      importIncognito: importIncognito,
    );

    // Collapse the play list to unique keys before matching (~7k keys for
    // ~200k plays) so the matcher resolves each track once.
    final keys = <SpotifyTrackKey>{
      for (final play in parsed.plays) play.trackKey,
    };
    final matches = matcher.matchAll(keys);

    final events = _builder.buildAll(
      parsed.plays,
      matches,
      userId: userId,
      clientKind: clientKind,
    );

    final matchedKeys =
        keys.where((key) => matches[key]?.isMatched ?? false).length;
    final matchedPlays = parsed.plays
        .where((play) => matches[play.trackKey]?.isMatched ?? false)
        .length;

    return SpotifyImportResult(
      events: events,
      summary: parsed.summary,
      trackMatchRate: keys.isEmpty ? 0.0 : matchedKeys / keys.length,
      playMatchRate:
          parsed.plays.isEmpty ? 0.0 : matchedPlays / parsed.plays.length,
    );
  }
}
