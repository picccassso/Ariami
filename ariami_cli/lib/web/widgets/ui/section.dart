import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// A titled block of dashboard content: heading, optional supporting line and
/// trailing action, then the block itself.
///
/// Replaces the ad-hoc `Text('SECTION NAME', letterSpacing: 1.5)` headings the
/// dashboard used to repeat in every widget.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.trailing,
  });

  final String title;
  final Widget child;

  /// One short line under the heading explaining what the block is for.
  final String? description;

  /// Action aligned to the end of the heading row (e.g. "Add user").
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(title, style: AppTheme.sectionTitle)),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(description!, style: AppTheme.meta),
        ],
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

/// Bordered surface that groups related rows or controls.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Overrides the default border — used by the destructive block.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.cardRadius,
        border: Border.all(color: borderColor ?? AppTheme.borderGrey),
      ),
      padding: padding ?? const EdgeInsets.all(20),
      child: child,
    );
  }
}

/// Hairline between rows inside an [AppCard].
class CardDivider extends StatelessWidget {
  const CardDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      color: AppTheme.borderGrey,
    );
  }
}
