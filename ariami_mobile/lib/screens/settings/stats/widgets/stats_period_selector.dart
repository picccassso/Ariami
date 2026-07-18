import 'package:flutter/material.dart';

import '../../../../services/stats/period_stats_loader.dart';

/// stats.fm-style period selector: a ‹ label › stepper over a
/// Day / Week / Month / Year / All granularity row. Paging is blocked
/// past today and before the account's first listen.
class StatsPeriodSelector extends StatelessWidget {
  const StatsPeriodSelector({
    super.key,
    required this.range,
    required this.canStepBack,
    required this.canStepForward,
    required this.onStep,
    required this.onPickDay,
    required this.onSelectGranularity,
  });

  final StatsRange range;
  final bool canStepBack;
  final bool canStepForward;
  final ValueChanged<int> onStep;
  final VoidCallback onPickDay;
  final ValueChanged<StatsRangeKind> onSelectGranularity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final granularities = <(StatsRangeKind, String)>[
      (StatsRangeKind.day, 'DAY'),
      (StatsRangeKind.week, 'WEEK'),
      (StatsRangeKind.month, 'MONTH'),
      (StatsRangeKind.year, 'YEAR'),
      (StatsRangeKind.all, 'ALL'),
    ];
    bool isSelected(StatsRangeKind kind) => switch (kind) {
          StatsRangeKind.day => range.isSingleDay,
          _ => range.kind == kind,
        };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _StepChevron(
                icon: Icons.chevron_left_rounded,
                enabled: canStepBack,
                colorScheme: colorScheme,
                onTap: () => onStep(-1),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Tapping the label jumps straight to the date picker in
                  // day mode.
                  onTap: range.isSingleDay ? onPickDay : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          range.title(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (range.isSingleDay) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              _StepChevron(
                icon: Icons.chevron_right_rounded,
                enabled: canStepForward,
                colorScheme: colorScheme,
                onTap: () => onStep(1),
              ),
            ],
          ),
          Row(
            children: [
              for (final entry in granularities)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _RangeChip(
                      label: entry.$2,
                      selected: isSelected(entry.$1),
                      onTap: () => onSelectGranularity(entry.$1),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small pill for the granularity row.
class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? colorScheme.onSecondary : colorScheme.onSurfaceVariant;
    final background = selected ? colorScheme.secondary : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

/// A ‹ / › paging chevron for the period stepper; greyed out at the bounds
/// of the account's listening history.
class _StepChevron extends StatelessWidget {
  const _StepChevron({
    required this.icon,
    required this.enabled,
    required this.colorScheme,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.35);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 26, color: color),
      ),
    );
  }
}
