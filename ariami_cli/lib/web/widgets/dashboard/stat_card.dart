import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// Compact metric tile: icon, number, label.
///
/// Sized by its own content rather than a grid aspect ratio, so a wide window
/// makes the tiles wider without making them taller.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final String count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            child: Icon(icon, size: 18, color: AppTheme.textPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -1,
                    height: 1.15,
                  ),
                ),
                Text(
                  label,
                  style: AppTheme.fieldLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
