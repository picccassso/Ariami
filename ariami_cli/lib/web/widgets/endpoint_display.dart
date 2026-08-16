import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Single LAN or Tailscale endpoint row (matches Desktop connection UX).
///
/// The address is the point of the row, so it is set in a monospace face and
/// stays selectable — people copy it into a phone or a browser bar.
class EndpointDisplay extends StatelessWidget {
  const EndpointDisplay({
    super.key,
    required this.label,
    required this.value,
    required this.badgeLabel,
    this.dense = false,
  });

  final String label;
  final String value;
  final String badgeLabel;

  /// Smaller typography for dense panels (e.g. QR sidebar).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: dense ? 12 : 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceRaised,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.borderGrey),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  fontSize: dense ? 9.5 : 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: dense ? 5 : 7),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: dense ? 15 : 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
            fontFamily: 'monospace',
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}
