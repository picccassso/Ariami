import 'package:flutter/material.dart';

void main() {
  final theme = ThemeData(
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (BuildContext context) => const Icon(Icons.arrow_back),
    ),
  );
  print(theme);
}
