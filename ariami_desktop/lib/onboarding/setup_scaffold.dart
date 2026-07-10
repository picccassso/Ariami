import 'package:flutter/material.dart';

import 'setup_help.dart';

/// Shared chrome for setup screens: back navigation at the top-left (when the
/// route can pop), an optional centered title, and the contextual-help icon at
/// the top-right — identical placement and behaviour on every step.
class SetupScreenScaffold extends StatelessWidget {
  const SetupScreenScaffold({
    super.key,
    this.title,
    this.helpTopic,
    this.allowBack = true,
    required this.body,
  });

  final String? title;
  final SetupHelpTopic? helpTopic;

  /// When false, no back button is shown even if the route can pop (used by
  /// screens that manage their own exit, like the scan-in-progress screen).
  final bool allowBack;

  final Widget body;

  @override
  Widget build(BuildContext context) {
    final canPop = allowBack && (Navigator.maybeOf(context)?.canPop() ?? false);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: canPop ? const BackButton() : null,
        title: title == null ? null : Text(title!),
        actions: [
          if (helpTopic != null) SetupHelpButton(topic: helpTopic!),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }
}
