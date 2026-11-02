import 'package:flutter/material.dart';

import '../overview_metrics.dart';
import 'tap_hint.dart';
import '../../../../utils/constants.dart';

class StatsOverviewCard extends StatelessWidget {
  const StatsOverviewCard({
    super.key,
    required this.metrics,
    required this.onPlaytimeTap,
    required this.showTapHint,
  });

  /// Exactly three metrics; the middle one is always PLAYTIME.
  final List<OverviewMetric> metrics;
  final VoidCallback onPlaytimeTap;
  final bool showTapHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(metric: metrics[0]),
            // The middle metric is always PLAYTIME; tapping it flips units.
            _StatItem(
              metric: metrics[1],
              onTap: onPlaytimeTap,
              pulse: showTapHint,
            ),
            _StatItem(metric: metrics[2]),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.metric, this.onTap, this.pulse = false});

  final OverviewMetric metric;
  final VoidCallback? onTap;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget item = Column(
      children: [
        Text(
          metric.value,
          style: AppTheme.display(34, color: colors.textPrimary)
              .copyWith(fontFeatures: AppTheme.tabular),
        ),
        const SizedBox(height: 6),
        Text(
          metric.label,
          style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
        ),
      ],
    );
    if (pulse) item = TapHint(child: item);
    if (onTap != null) {
      item = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: item,
      );
    }
    return item;
  }
}

/// One-time explainer shown right after the first PLAYTIME tap, so the
/// value switching units doesn't read as a glitch.
void showPlaytimeHintDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Playtime units'),
      content: const Text(
        'Tapping Playtime cycles it through hours, minutes, and compact '
        'minutes — Avg daily follows along when it\'s shown. Keep tapping '
        'to move through them.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
