import 'package:ariami_core/models/host_controls.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/layout.dart';
import '../ui/page_shell.dart';
import '../ui/section.dart';
import '../ui/status_pill.dart';

/// Shown after a reset finishes. The server stops itself at that point, so
/// the dashboard has nothing left to talk to — say so plainly instead of
/// letting every panel fail its next refresh.
class ServerResetCompletePanel extends StatelessWidget {
  const ServerResetCompletePanel({super.key, required this.outcome});

  final HostResetOutcome outcome;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      maxWidth: AppLayout.proseMaxWidth,
      centerVertically: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            outcome.success
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            size: 44,
            color: outcome.success ? AppTheme.success : AppTheme.warning,
          ),
          const SizedBox(height: 20),
          Text(
            outcome.success ? 'Reset complete' : 'Reset finished with problems',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            outcome.message,
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary,
              height: 1.55,
            ),
          ),
          if (outcome.failedPaths.isNotEmpty) ...[
            const SizedBox(height: 20),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Could not remove', style: AppTheme.fieldLabel),
                  const SizedBox(height: 8),
                  for (final path in outcome.failedPaths)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        path,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const NoticeBanner(
            icon: Icons.terminal_rounded,
            tone: StatusTone.neutral,
            message: 'Run "ariami_cli start" on the machine to set Ariami up '
                'again, then reopen this page.',
          ),
        ],
      ),
    );
  }
}
