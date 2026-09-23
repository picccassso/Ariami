import 'package:flutter/material.dart';
import '../../services/theme_service.dart';
import '../../utils/constants.dart';
import 'ambient_backdrop.dart';

/// Forces the setup theme with the ambient navy backdrop over a setup/auth screen.
///
/// Pre-connection surfaces use the navy setup palette drawn from the app icon
/// with frosted glass and an ambient backdrop.
class SetupDarkTheme extends StatelessWidget {
  const SetupDarkTheme({super.key, this.child, this.builder})
      : assert(child != null || builder != null,
            'Either child or builder must be provided');

  final Widget? child;
  final WidgetBuilder? builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        final theme = AppTheme.setup();
        return Theme(
          data: theme,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(
                child: AmbientBackdrop(layoutSeed: 0x5E70),
              ),
              Builder(
                builder: (themedContext) =>
                    builder != null ? builder!(themedContext) : child!,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Paints the navy setup glow behind a setup screen, whose own Scaffold must
/// then be transparent.
class SetupBackdrop extends StatelessWidget {
  const SetupBackdrop({super.key, required this.child});

  final Widget child;

  static final ThemeData _setupTheme = AppTheme.setup();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Theme(
            data: _setupTheme,
            child: const AmbientBackdrop(layoutSeed: 0x5E70),
          ),
        ),
        child,
      ],
    );
  }
}
