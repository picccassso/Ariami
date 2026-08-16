import 'package:flutter/material.dart';

import '../../utils/constants.dart';

enum StatusTone { positive, neutral, caution, negative }

extension on StatusTone {
  Color get color => switch (this) {
        StatusTone.positive => AppTheme.success,
        StatusTone.neutral => AppTheme.textSecondary,
        StatusTone.caution => AppTheme.warning,
        StatusTone.negative => AppTheme.danger,
      };
}

/// Small dot-and-label chip for a live state ("Running", "Scanning", "Stopped").
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.pulse,
    this.busy = false,
  });

  final String label;
  final StatusTone tone;

  /// Fades the dot to show the state is live rather than a stale reading.
  final Animation<double>? pulse;

  /// Swaps the dot for a spinner (e.g. while a scan is running).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = tone.color;

    Widget indicator = busy
        ? SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: color),
          )
        : Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          );

    if (!busy && pulse != null) {
      indicator = FadeTransition(opacity: pulse!, child: indicator);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width inline notice used for warnings and confirmations.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.tone,
    this.action,
  });

  final IconData icon;
  final String message;
  final StatusTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = tone.color;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
                height: 1.45,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            action!,
          ],
        ],
      ),
    );
  }
}
