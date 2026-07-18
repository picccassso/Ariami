import 'package:flutter/material.dart';

import '../overview_metrics.dart';
import 'tap_hint.dart';

/// The overview card showing total stats (dynamic based on tab and range).
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

/// A single stat item in the grid.
class _StatItem extends StatelessWidget {
  const _StatItem({required this.metric, this.onTap, this.pulse = false});

  final OverviewMetric metric;
  final VoidCallback? onTap;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget item = Column(
      children: [
        Text(
          metric.value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          metric.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.grey[500] : Colors.grey[600],
            letterSpacing: 1.0,
          ),
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
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
      title: Text(
        'PLAYTIME UNITS',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      content: Text(
        'Tapping PLAYTIME cycles it through hours, minutes, and compact '
        'minutes — AVG DAILY follows along when it\'s shown. Keep tapping '
        'to move through them.',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'GOT IT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
      ],
    ),
  );
}
