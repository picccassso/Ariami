import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import 'glass_panel.dart';

/// The frosted card the pre-connection forms (connect, sign in, register)
/// float on, centred over the ambient backdrop and scrollable when the
/// screen is short.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 60,
                  offset: const Offset(0, 24),
                ),
              ],
            ),
            child: GlassPanel(
              radius: 28,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The glowing icon disc that heads an [AuthCard].
class AuthBadge extends StatelessWidget {
  const AuthBadge({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.glowA, colors.glowB],
          ),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.glowA.withValues(alpha: 0.55),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, size: 34, color: Colors.white),
      ),
    );
  }
}
