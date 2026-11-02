import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// A settings section's title: a hairline rule, then the title in condensed
/// heading type, sentence case and shown as given, as on Premium Desktop.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Text(text, style: AppTheme.heading(20, color: colors.textPrimary)),
    );
  }
}

/// A small sentence-case label naming a group of controls or a figure, in
/// place of tracked-out capitals.
class SettingsLabel extends StatelessWidget {
  const SettingsLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style:
            AppTheme.heading(14, color: color ?? context.colors.textSecondary),
      );
}
