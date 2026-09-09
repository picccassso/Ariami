import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Single LAN or Tailscale endpoint row (matches Desktop connection UX).
///
/// The address is the point of the row, so it is set in a monospace face and
/// stays selectable — people copy it into a phone or a browser bar.
class EndpointDisplay extends StatefulWidget {
  const EndpointDisplay({
    super.key,
    required this.label,
    required this.value,
    this.alias,
    required this.badgeLabel,
    this.dense = false,
  });

  final String label;
  final String value;
  final String? alias;
  final String badgeLabel;

  /// Smaller typography for dense panels (e.g. QR sidebar).
  final bool dense;

  @override
  State<EndpointDisplay> createState() => _EndpointDisplayState();
}

class _EndpointDisplayState extends State<EndpointDisplay> {
  bool _isRevealed = false;

  @override
  Widget build(BuildContext context) {
    final hasAlias = widget.alias != null && widget.alias!.trim().isNotEmpty;
    final displayValue =
        (hasAlias && !_isRevealed) ? widget.alias! : widget.value;
    final isMonospace = !hasAlias || _isRevealed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.label,
              style: TextStyle(
                fontSize: widget.dense ? 12 : 13,
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
                widget.badgeLabel,
                style: TextStyle(
                  fontSize: widget.dense ? 9.5 : 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            if (hasAlias) ...[
              const SizedBox(width: 6),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: widget.dense ? 16 : 18,
                splashRadius: widget.dense ? 14 : 16,
                icon: Icon(
                  _isRevealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppTheme.textTertiary,
                ),
                tooltip: _isRevealed ? 'Hide raw address' : 'Reveal raw address',
                onPressed: () {
                  setState(() {
                    _isRevealed = !_isRevealed;
                  });
                },
              ),
            ],
          ],
        ),
        SizedBox(height: widget.dense ? 5 : 7),
        SelectableText(
          displayValue,
          style: TextStyle(
            fontSize: widget.dense ? 15 : 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
            fontFamily: isMonospace ? 'monospace' : null,
            letterSpacing: isMonospace ? -0.2 : 0,
          ),
        ),
      ],
    );
  }
}
