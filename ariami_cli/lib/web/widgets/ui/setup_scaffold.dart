import 'package:flutter/material.dart';

import '../../onboarding/setup_help.dart';
import '../../utils/constants.dart';
import '../../utils/layout.dart';
import 'page_shell.dart';

/// One step of the setup flow.
///
/// Every step gets the same shape — where you are, what this step is, why it
/// matters, the controls, then back/next — so the flow reads as one thing
/// rather than five screens that happen to follow each other.
class SetupScaffold extends StatelessWidget {
  const SetupScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.description,
    required this.child,
    this.icon,
    this.helpTopic,
    this.primaryAction,
    this.secondaryAction,
    this.banner,
    this.maxWidth = AppLayout.proseMaxWidth,
  });

  /// 1-based position in [totalSteps]; null hides the step indicator.
  final int? step;
  final String title;
  final String description;
  final Widget child;
  final IconData? icon;
  final SetupHelpTopic? helpTopic;

  /// Bottom-right action ("Continue"), and the quieter one beside it ("Back").
  final Widget? primaryAction;
  final Widget? secondaryAction;

  /// Optional notice pinned above the content (e.g. a port-fallback message).
  final Widget? banner;

  final double maxWidth;

  static const int totalSteps = 5;

  @override
  Widget build(BuildContext context) {
    final hasFooter = primaryAction != null || secondaryAction != null;

    return Scaffold(
      body: Column(
        children: [
          if (banner != null) banner!,
          Expanded(
            child: PageShell(
              maxWidth: maxWidth,
              centerVertically: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (step != null)
                        Expanded(child: _StepIndicator(step: step!))
                      else
                        const Spacer(),
                      if (helpTopic != null)
                        SetupHelpButton(topic: helpTopic!),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (icon != null) ...[
                    _StepIcon(icon: icon!),
                    const SizedBox(height: 22),
                  ],
                  Text(title, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.textSecondary,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 28),
                  child,
                  if (hasFooter) ...[
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        if (secondaryAction != null) secondaryAction!,
                        const Spacer(),
                        if (primaryAction != null) primaryAction!,
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Step $step of ${SetupScaffold.totalSteps}',
          style: AppTheme.meta.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              for (var i = 1; i <= SetupScaffold.totalSteps; i++) ...[
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: i <= step ? Colors.white : AppTheme.borderGrey,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                if (i < SetupScaffold.totalSteps) const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlack,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppTheme.borderGrey),
        ),
        child: Icon(icon, size: 24, color: AppTheme.textPrimary),
      ),
    );
  }
}
