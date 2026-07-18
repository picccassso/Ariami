import 'package:ariami_core/ariami_core.dart' show ListeningPeriodStats;

import '../../../models/artist_stats.dart';
import '../../../services/stats/streaming_stats_service.dart';
import 'playtime_format.dart';

/// One label/value pair on the overview card.
typedef OverviewMetric = ({String label, String value});

/// The three overview-card metrics for the current tab and range. The middle
/// metric is always PLAYTIME, formatted (and recorded) through [playtime].
List<OverviewMetric> computeOverviewMetrics({
  required int tabIndex,
  required bool useAllTimeData,
  required ListeningPeriodStats? periodStats,
  required StreamingStatsService statsService,
  required List<ArtistStats>? creditedArtists,
  required PlaytimeFormat playtime,
}) {
  String metric1Label;
  String metric1Value;
  String metric2Label;
  String metric2Value;
  String metric3Label;
  String metric3Value;

  if (!useAllTimeData) {
    final stats = periodStats;
    metric1Label = switch (tabIndex) {
      1 => 'ARTISTS',
      2 => 'ALBUMS',
      _ => 'SONGS',
    };
    metric1Value = switch (tabIndex) {
      1 => '${stats?.artists.length ?? 0}',
      2 => '${stats?.albums.length ?? 0}',
      _ => '${stats?.songs.length ?? 0}',
    };
    metric2Label = 'PLAYTIME';
    metric2Value = playtime
        .formatPlaytime(Duration(milliseconds: stats?.totalListenedMs ?? 0));
    metric3Label = 'PLAYS';
    metric3Value = '${stats?.totalPlays ?? 0}';
  } else {
    switch (tabIndex) {
      case 0: // Tracks
        final stats = statsService.getTotalStats();
        final avgData = statsService.getAverageDailyTime();
        metric1Label = 'SONGS';
        metric1Value = stats.totalSongsPlayed.toString();
        metric2Label = 'PLAYTIME';
        metric2Value = playtime.formatPlaytime(stats.totalTimeStreamed);
        metric3Label = 'AVG DAILY';
        metric3Value = playtime.formatDurationShort(avgData.perCalendarDay);
        break;

      case 1: // Artists
        final avgData = statsService.getAverageDailyTime();
        final credited = creditedArtists;
        final artistCount = credited != null
            ? credited.length
            : statsService.getTopArtists(limit: 1000).length;
        // With credited artists every collaborator receives the full
        // listened time, so summing per-artist time would double-count
        // collabs — the account total is the honest playtime figure.
        final totalTime = credited != null
            ? statsService.getTotalStats().totalTimeStreamed
            : statsService.getTopArtists(limit: 1000).fold<Duration>(
                  Duration.zero,
                  (sum, artist) => sum + artist.totalTime,
                );
        metric1Label = 'ARTISTS';
        metric1Value = artistCount.toString();
        metric2Label = 'PLAYTIME';
        metric2Value = playtime.formatPlaytime(totalTime);
        metric3Label = 'AVG DAILY';
        metric3Value = playtime.formatDurationShort(avgData.perCalendarDay);
        break;

      case 2: // Albums
        final avgData = statsService.getAverageDailyTime();
        final albums = statsService.getTopAlbums(limit: 1000);
        final totalTime = albums.fold<Duration>(
          Duration.zero,
          (sum, album) => sum + album.totalTime,
        );
        metric1Label = 'ALBUMS';
        metric1Value = albums.length.toString();
        metric2Label = 'PLAYTIME';
        metric2Value = playtime.formatPlaytime(totalTime);
        metric3Label = 'AVG DAILY';
        metric3Value = playtime.formatDurationShort(avgData.perCalendarDay);
        break;

      default:
        metric1Label = 'SONGS';
        metric1Value = '0';
        metric2Label = 'PLAYTIME';
        playtime.lastTotalMs = 0;
        metric2Value = '0h';
        metric3Label = 'AVG';
        metric3Value = '0m';
    }
  }

  return [
    (label: metric1Label, value: metric1Value),
    (label: metric2Label, value: metric2Value),
    (label: metric3Label, value: metric3Value),
  ];
}
