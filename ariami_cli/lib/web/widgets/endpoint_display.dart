import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Single LAN or Tailscale endpoint row (matches Desktop connection UX).
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
    final titleSize = dense ? 10.0 : 11.0;
    final valueSize = dense ? 16.0 : 20.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.borderGrey),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  fontSize: dense ? 9 : 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: dense ? 6 : 8),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: valueSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
