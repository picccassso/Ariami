import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/layout.dart';

/// Label / value row with a leading icon and an optional trailing control.
///
/// The dashboard's workhorse: it is the web counterpart of Ariami Desktop's
/// `InfoCard`, so the two dashboards read the same way. Rows stack inside an
/// `AppCard` separated by `CardDivider`.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.isActive = true,
    this.trailing,
    this.valueIsPath = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  /// Dims the icon and value when the thing being described is off or unset.
  final bool isActive;

  final Widget? trailing;

  /// Renders the value in a monospace face and lets it wrap — for file paths
  /// and addresses, which are read character by character.
  final bool valueIsPath;

  @override
  Widget build(BuildContext context) {
    final isCompact = AppLayout.of(context) == WidthClass.compact;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTheme.fieldLabel),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: valueIsPath ? 13.5 : 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: valueIsPath ? 0 : -0.2,
            height: valueIsPath ? 1.45 : 1.25,
            fontFamily: valueIsPath ? 'monospace' : null,
            color: isActive ? AppTheme.textPrimary : AppTheme.textTertiary,
          ),
          maxLines: valueIsPath ? 3 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(subtitle!, style: AppTheme.meta),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _IconChip(icon: icon, isActive: isActive),
          const SizedBox(width: 14),
          Expanded(child: text),
          if (trailing != null) ...[
            SizedBox(width: isCompact ? 8 : 16),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.isActive});

  final IconData icon;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.borderGrey),
      ),
      child: Icon(
        icon,
        size: 19,
        color: isActive ? AppTheme.textPrimary : AppTheme.textTertiary,
      ),
    );
  }
}
