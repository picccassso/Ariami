import 'package:flutter/material.dart';

/// One titled block of plain-language help text inside a [SetupHelpTopic].
class SetupHelpSection {
  const SetupHelpSection({required this.heading, required this.body});

  final String heading;
  final String body;
}

/// Contextual help for one onboarding screen: a title plus short sections.
///
/// Topics live in `onboarding_copy.dart` so the words stay separate from the
/// widgets that display them.
class SetupHelpTopic {
  const SetupHelpTopic({required this.title, required this.sections});

  final String title;
  final List<SetupHelpSection> sections;
}

/// The standard top-right information icon used on every setup screen.
///
/// Opens the shared contextual-help dialog for [topic]. Focus returns to the
/// button (or whatever held it) when the dialog closes — the dialog route's
/// focus scope handles that automatically.
class SetupHelpButton extends StatelessWidget {
  const SetupHelpButton({super.key, required this.topic});

  final SetupHelpTopic topic;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'About this step',
      icon: const Icon(Icons.info_outline_rounded, size: 20),
      onPressed: () => showSetupHelp(context, topic),
    );
  }
}

/// Shows the reusable contextual-help dialog for [topic].
///
/// Dismissible with the close button, the Escape key, and a click on the
/// barrier. Returns once the dialog has been closed.
Future<void> showSetupHelp(BuildContext context, SetupHelpTopic topic) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close help',
    builder: (dialogContext) => _SetupHelpDialog(topic: topic),
  );
}

class _SetupHelpDialog extends StatelessWidget {
  const _SetupHelpDialog({required this.topic});

  final SetupHelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final secondaryText = scheme.onSurface.withValues(alpha: 0.7);
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Semantics(
          container: true,
          label: 'Help: ${topic.title}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 20, color: secondaryText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        topic.title,
                        style: textTheme.titleLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close help',
                      autofocus: true,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final section in topic.sections) ...[
                        Text(
                          section.heading,
                          style: textTheme.titleSmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          section.body,
                          style: textTheme.bodyMedium?.copyWith(
                            color: secondaryText,
                            height: 1.45,
                          ),
                        ),
                        if (section != topic.sections.last)
                          const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
