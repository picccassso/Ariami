import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/stats_range.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/library_controller.dart';
import '../services/listening_stats_controller.dart';
import '../services/player_navigator.dart';
import '../theme/player_theme.dart';
import 'settings/stats/stats_models.dart';
import 'settings/stats/widgets/stats_list_items.dart';

/// Home's "Most played this month": the five songs played most this calendar
/// month, ranked, from the server's listening stats. Clicking one plays it,
/// with the rest of the five queued after it. Renders nothing while offline,
/// before there is any listening this month, or against a server without
/// period stats.
class HomeMostPlayed extends StatefulWidget {
  const HomeMostPlayed({super.key});

  static const _count = 5;

  /// The server ranks a period by listening time, so ask for enough of the
  /// top to re-rank by plays without missing a short song played often.
  static const _fetch = 50;

  @override
  State<HomeMostPlayed> createState() => _HomeMostPlayedState();
}

class _HomeMostPlayedState extends State<HomeMostPlayed> {
  late final Future<ListeningPeriodStats?> _month;

  @override
  void initState() {
    super.initState();
    final bounds = StatsRange.month.bounds()!;
    _month = context.read<ListeningStatsController>().loadPeriodStats(
          fromDay: bounds.from,
          toDay: bounds.to,
          limit: HomeMostPlayed._fetch,
        );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ListeningPeriodStats?>(
      future: _month,
      builder: (context, snapshot) {
        final songs = [...?snapshot.data?.songs]..sort((a, b) {
            final byPlays = b.playCount.compareTo(a.playCount);
            return byPlays != 0
                ? byPlays
                : b.listenedMs.compareTo(a.listenedMs);
          });
        if (songs.length > HomeMostPlayed._count) {
          songs.removeRange(HomeMostPlayed._count, songs.length);
        }
        if (songs.isEmpty) return const SizedBox.shrink();

        final library = context.watch<LibraryController>();
        final tracks = [
          for (final song in songs) library.songById(song.songId)
        ];
        final playable = tracks.whereType<Track>().toList();
        final colors = context.colors;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Most played this month',
                  style: PlayerTheme.heading(22, color: colors.textPrimary),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.read<PlayerNavigator>().go(
                        const PlayerView(
                          PlayerViewKind.settings,
                          id: 'listening-stats',
                        ),
                      ),
                  child: const Text('Listening stats'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < songs.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: ListeningRankRow(
                  rank: i + 1,
                  item: ListeningRankItem(
                    title: songs[i].songTitle ?? tracks[i]?.title ?? 'Unknown',
                    subtitle:
                        songs[i].songArtist ?? tracks[i]?.artist ?? 'Unknown',
                    detail: '${songs[i].playCount} '
                        '${songs[i].playCount == 1 ? 'play' : 'plays'}',
                    albumId: songs[i].albumId,
                    songId: songs[i].songId,
                  ),
                  onTap: tracks[i] == null
                      ? null
                      : () => context
                          .read<AudioController>()
                          .playTrack(tracks[i]!, context: playable),
                ),
              ),
            const SizedBox(height: 28),
          ],
        );
      },
    );
  }
}
