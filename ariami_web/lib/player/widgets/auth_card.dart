import 'package:flutter/material.dart';

import '../theme/player_theme.dart';
import 'glass_panel.dart';

/// The frosted card the pre-connection forms (connect, sign in, register)
/// float on, centred over the ambient backdrop and scrollable when the
/// window is short.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth + 72),
          child: GlassPanel(
            radius: 24,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 36, 36, 28),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class AuthBadge extends StatelessWidget {
  const AuthBadge({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surfaceHigh,
          border: Border.all(color: colors.border),
        ),
        child: Icon(icon, size: 26, color: colors.textPrimary),
      ),
    );
  }
}
