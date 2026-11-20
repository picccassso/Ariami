import 'package:ariami_core/services/stats/stats_range.dart';
import 'package:flutter/material.dart';

import '../../../../theme/motion.dart';
import '../../../../theme/player_theme.dart';

/// stats.fm-style period selector: a ‹ label › stepper over a
/// Day / Week / Month / Year / All granularity row.
///
/// Designed as a frosted glass floating dock that harmonizes with the
/// ambient backdrop and the stats section's pill chips.
class StatsPeriodSelector extends StatelessWidget {
  const StatsPeriodSelector({
    super.key,
    required this.range,
    required this.canStepBack,
    required this.canStepForward,
    required this.onStep,
    required this.onSelectGranularity,
    required this.onPickDay,
  });

  final StatsRange range;
  final bool canStepBack;
  final bool canStepForward;
  final ValueChanged<int> onStep;
  final ValueChanged<StatsRangeKind> onSelectGranularity;

  /// Opens the specific-day date picker; invoked by tapping the label while
  /// in day mode.
  final VoidCallback onPickDay;

  @override
  Widget build(BuildContext context) {
    final granularities = <(StatsRangeKind, String)>[
      (StatsRangeKind.day, 'Day'),
      (StatsRangeKind.week, 'Week'),
      (StatsRangeKind.month, 'Month'),
      (StatsRangeKind.year, 'Year'),
      (StatsRangeKind.all, 'All'),
    ];
    bool isSelected(StatsRangeKind kind) => switch (kind) {
          StatsRangeKind.day => range.isSingleDay,
          _ => range.kind == kind,
        };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.popover,
            borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
            border: Border.all(color: context.colors.border),
          ),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _StepChevron(
                    icon: Icons.chevron_left_rounded,
                    enabled: canStepBack,
                    tooltip: 'Previous period',
                    onTap: () => onStep(-1),
                  ),
                  Expanded(
                    child: _PeriodTitleButton(
                      range: range,
                      onTap: range.isSingleDay ? onPickDay : null,
                    ),
                  ),
                  _StepChevron(
                    icon: Icons.chevron_right_rounded,
                    enabled: canStepForward,
                    tooltip: 'Next period',
                    onTap: () => onStep(1),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final entry in granularities)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: _GranularityChip(
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
        ),
      ),
    );
  }
}

class _GranularityChip extends StatefulWidget {
  const _GranularityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_GranularityChip> createState() => _GranularityChipState();
}

class _GranularityChipState extends State<_GranularityChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;

    // When selected: bright dynamic accent pill (matches "Tracks").
    // When unselected: translucent surfaceHover (matches "Artists"/"Albums"),
    // brightening slightly on hover.
    final baseColor = _hovered
        ? context.colors.surfaceHover
        : context.colors.surfaceHover.withValues(alpha: 0.65);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? scheme.secondary : baseColor,
            borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
          ),
          child: AnimatedDefaultTextStyle(
            duration: Motion.fast,
            curve: Motion.standard,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected
                  ? scheme.onSecondary
                  : (_hovered
                      ? context.colors.textPrimary
                      : context.colors.textPrimary.withValues(alpha: 0.85)),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class _StepChevron extends StatefulWidget {
  const _StepChevron({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_StepChevron> createState() => _StepChevronState();
}

class _StepChevronState extends State<_StepChevron> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Widget button = MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        if (widget.enabled) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _hovered && widget.enabled
                ? context.colors.textPrimary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: widget.enabled
                ? context.colors.textPrimary
                : context.colors.textSecondary.withValues(alpha: 0.35),
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.enabled) {
      button = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }

    return button;
  }
}

class _PeriodTitleButton extends StatefulWidget {
  const _PeriodTitleButton({
    required this.range,
    required this.onTap,
  });

  final StatsRange range;
  final VoidCallback? onTap;

  @override
  State<_PeriodTitleButton> createState() => _PeriodTitleButtonState();
}

class _PeriodTitleButtonState extends State<_PeriodTitleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSingleDay = widget.range.isSingleDay;
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.range.title(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          if (isSingleDay) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.calendar_today_rounded,
              size: 13,
              color: _hovered
                  ? context.colors.textPrimary
                  : context.colors.textSecondary,
            ),
          ],
        ],
      ),
    );

    if (!isSingleDay || widget.onTap == null) {
      return content;
    }

    content = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          decoration: BoxDecoration(
            color: _hovered
                ? context.colors.textPrimary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
          ),
          child: content,
        ),
      ),
    );

    return Tooltip(
      message: 'Choose date',
      waitDuration: const Duration(milliseconds: 500),
      child: content,
    );
  }
}
