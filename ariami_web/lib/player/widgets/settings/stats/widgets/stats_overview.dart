import 'package:flutter/material.dart';

import '../../../../services/listening_stats_controller.dart';
import '../../../../theme/player_theme.dart';
import '../playtime_format.dart';
import '../stats_models.dart';

class StatsOverview extends StatelessWidget {
  const StatsOverview({
    super.key,
    required this.category,
    required this.stats,
    required this.unit,
    required this.pulsePlaytime,
    required this.onPlaytimeTap,
  });

  final StatsCategory category;
  final ListeningStatsSnapshot stats;
  final PlaytimeUnit unit;
  final bool pulsePlaytime;
  final VoidCallback onPlaytimeTap;

  String _formatToggled(int milliseconds) => switch (unit) {
        PlaytimeUnit.hours => formatListeningTime(milliseconds),
        PlaytimeUnit.minutes => formatListeningMinutes(milliseconds),
        PlaytimeUnit.minutesCompact =>
          formatListeningMinutesCompact(milliseconds),
      };

  @override
  Widget build(BuildContext context) {
    final (countLabel, count) = switch (category) {
      StatsCategory.tracks => ('Tracks', stats.songs.length),
      StatsCategory.artists => ('Artists', stats.artists.length),
      StatsCategory.albums => ('Albums', stats.albums.length),
    };
    Widget playtime = _StatsMetric(
      label: 'Playtime',
      value: _formatToggled(stats.totalListenedMs),
    );
    if (pulsePlaytime) playtime = _ClickHint(child: playtime);
    return Row(
      children: [
        Expanded(child: _StatsMetric(label: countLabel, value: '$count')),
        Container(width: 1, height: 42, color: context.colors.border),
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPlaytimeTap,
              child: playtime,
            ),
          ),
        ),
        Container(width: 1, height: 42, color: context.colors.border),
        Expanded(
          child: _StatsMetric(
            label: 'Daily average',
            value: _formatToggled(stats.averageDailyMs),
          ),
        ),
      ],
    );
  }
}

class _StatsMetric extends StatelessWidget {
  const _StatsMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PlayerTheme.display(36, color: context.colors.textPrimary)
              .copyWith(fontFeatures: PlayerTheme.tabular),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}

/// Overlays a little mouse cursor that periodically clicks the child — the
/// metric dips under the click and a ripple ring expands, demonstrating the
/// real gesture. Only mounted while the PLAYTIME hint is still pending.
class _ClickHint extends StatefulWidget {
  const _ClickHint({required this.child});

  final Widget child;

  @override
  State<_ClickHint> createState() => _ClickHintState();
}

class _ClickHintState extends State<_ClickHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  static double _seg(double t, double from, double to, Curve curve) =>
      curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colors.textPrimary;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        // Loop: cursor slides in (0–.25), clicks (.25–.35), ripple +
        // release (.35–.7), fades out (.7–.85), rests (.85–1).
        final approach = _seg(t, 0.0, 0.25, Curves.easeOutCubic);
        final press = t < 0.25
            ? 0.0
            : t < 0.35
                ? _seg(t, 0.25, 0.35, Curves.easeIn)
                : 1.0 - _seg(t, 0.35, 0.5, Curves.easeOut);
        final ripple = _seg(t, 0.33, 0.7, Curves.easeOut);
        final visible = approach * (1.0 - _seg(t, 0.7, 0.85, Curves.easeIn));

        const target = Offset(12, -5);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.scale(scale: 1.0 - 0.06 * press, child: child),
            Positioned.fill(
              child: IgnorePointer(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    if (ripple > 0 && ripple < 1)
                      Transform.translate(
                        offset: target,
                        child: Opacity(
                          opacity: (1.0 - ripple) * 0.7,
                          child: Container(
                            width: 8 + 24 * ripple,
                            height: 8 + 24 * ripple,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: color, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    Transform.translate(
                      // The (flipped) arrow's tip is its top-left corner, so
                      // the icon centre trails the click point down-right; it
                      // slides in from there and dips slightly on the click.
                      offset: target +
                          Offset(
                            9 + 20 * (1 - approach),
                            9 + 14 * (1 - approach) - 1.5 * press,
                          ),
                      child: Opacity(
                        opacity: visible.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 1.0 - 0.15 * press,
                          child: Transform.flip(
                            flipX: true,
                            child: Icon(
                              Icons.near_me_rounded,
                              size: 19,
                              color: color,
                              shadows: const [
                                Shadow(color: Colors.black38, blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
