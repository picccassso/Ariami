import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/layout.dart';
import '../ui/section.dart';

/// The things an owner does to this server often enough to want one click:
/// connect another device, and rescan the library.
class ServerActionsSection extends StatelessWidget {
  const ServerActionsSection({
    super.key,
    required this.isScanning,
    required this.onShowQrCode,
    required this.onRescanLibrary,
  });

  final bool isScanning;
  final VoidCallback onShowQrCode;
  final VoidCallback onRescanLibrary;

  @override
  Widget build(BuildContext context) {
    final isCompact = AppLayout.of(context) == WidthClass.compact;

    final buttons = <Widget>[
      OutlinedButton.icon(
        onPressed: onShowQrCode,
        icon: const Icon(Icons.qr_code_2_rounded, size: 19),
        label: const Text('Connect a device'),
        style: _actionStyle,
      ),
      OutlinedButton.icon(
        onPressed: isScanning ? null : onRescanLibrary,
        icon: isScanning
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded, size: 19),
        label: Text(isScanning ? 'Scanning…' : 'Rescan library'),
        style: _actionStyle,
      ),
    ];

    return Section(
      title: 'Quick actions',
      child: isCompact
          ? Column(
              children: [
                for (final button in buttons) ...[
                  SizedBox(width: double.infinity, child: button),
                  if (button != buttons.last) const SizedBox(height: 10),
                ],
              ],
            )
          : Row(
              children: [
                for (final button in buttons) ...[
                  Expanded(child: button),
                  if (button != buttons.last) const SizedBox(width: 12),
                ],
              ],
            ),
    );
  }

  static final ButtonStyle _actionStyle = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 18),
  );
}

/// Destructive operations, kept visually separate and behind a typed
/// confirmation so nobody reaches them by accident.
class DangerZoneSection extends StatelessWidget {
  const DangerZoneSection({
    super.key,
    required this.enabled,
    required this.onResetAriami,
  });

  /// False when the host does not support resetting itself.
  final bool enabled;
  final VoidCallback onResetAriami;

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Danger zone',
      child: AppCard(
        borderColor: AppTheme.danger.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reset Ariami',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              enabled
                  ? 'Clear this server\'s setup, or every account and the '
                      'library database. Ariami never deletes your music '
                      'files. The server stops once the reset finishes.'
                  : 'Resetting from the dashboard is not available on this '
                      'server. Run "ariami_cli reset" on the machine instead.',
              style: AppTheme.meta,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: enabled ? onResetAriami : null,
              icon: const Icon(Icons.restart_alt_rounded, size: 19),
              label: const Text('Reset Ariami…'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
