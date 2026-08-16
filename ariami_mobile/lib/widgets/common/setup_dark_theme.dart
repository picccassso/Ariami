import 'package:flutter/material.dart';
import '../../services/theme_service.dart';

/// Forces the dark theme over a setup/auth screen.
///
/// The setup flow is designed on a fixed black background, but its text and
/// icons resolve through the ambient theme. Under the light app theme that
/// makes them black-on-black and invisible, so these screens must always
/// render with the dark palette regardless of system brightness.
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
      builder: (context, _) => Theme(
        data: ThemeService().darkTheme,
        child: Builder(
          builder: (themedContext) =>
              builder != null ? builder!(themedContext) : child!,
        ),
      ),
    );
  }
}
