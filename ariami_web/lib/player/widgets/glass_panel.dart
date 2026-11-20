import 'package:flutter/material.dart';

import '../theme/player_theme.dart';

/// A frosted panel of the player shell: translucent [PlayerColors.panel] fill
/// over the ambient backdrop, a hairline edge and a soft top highlight that
/// catches the "light" like a pane of glass.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = PlayerTheme.panelRadius,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              colors.textPrimary.withValues(alpha: 0.025),
              colors.panel,
            ),
            colors.panel,
          ],
          stops: const [0, 0.35],
        ),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }
}
