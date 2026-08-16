import 'package:ariami_core/models/host_controls.dart';
import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../ui/info_row.dart';
import '../ui/section.dart';
import 'transcode_slots_dialog.dart' show formatTranscodeSlotsDisplay;

/// Machine-level settings for this server: the library folder, how many
/// transcodes run at once, and whether Ariami comes back after a reboot.
///
/// Mirrors the Configuration block on Ariami Desktop's Server tab.
class ServerConfigurationSection extends StatelessWidget {
  const ServerConfigurationSection({
    super.key,
    required this.hostControls,
    required this.isLoadingHostControls,
    required this.isSavingAutostart,
    required this.onToggleAutostart,
    required this.onChangeMusicFolder,
    required this.transcodeSlotsSnapshot,
    required this.isLoadingTranscodeSlots,
    required this.isSavingTranscodeSlots,
    required this.transcodeSlotsError,
    required this.onEditTranscodeSlots,
  });

  /// Null when the host does not offer these controls (or they failed to
  /// load); the folder and autostart rows are hidden in that case.
  final HostControlsSnapshot? hostControls;
  final bool isLoadingHostControls;
  final bool isSavingAutostart;
  final ValueChanged<bool> onToggleAutostart;
  final VoidCallback onChangeMusicFolder;

  final TranscodeSlotsSnapshot? transcodeSlotsSnapshot;
  final bool isLoadingTranscodeSlots;
  final bool isSavingTranscodeSlots;
  final String? transcodeSlotsError;
  final VoidCallback onEditTranscodeSlots;

  @override
  Widget build(BuildContext context) {
    final host = hostControls;
    final transcode = transcodeSlotsSnapshot;
    final transcodeBusy = isLoadingTranscodeSlots || isSavingTranscodeSlots;

    final rows = <Widget>[];

    if (host != null) {
      final folder = host.musicFolderPath;
      rows.add(
        InfoRow(
          icon: Icons.folder_rounded,
          label: 'Music folder',
          value: folder == null || folder.isEmpty ? 'Not configured' : folder,
          isActive: folder != null && folder.isNotEmpty,
          valueIsPath: folder != null && folder.isNotEmpty,
          subtitle: 'Ariami reads this folder. It never moves, changes or '
              'uploads your files.',
          trailing: OutlinedButton(
            onPressed: onChangeMusicFolder,
            child: const Text('Change'),
          ),
        ),
      );
    }

    rows.add(
      InfoRow(
        icon: Icons.speed_rounded,
        label: 'Transcode slots',
        isActive: transcodeSlotsError == null,
        value: switch ((transcodeBusy, transcodeSlotsError, transcode)) {
          (true, _, _) => 'Loading…',
          (_, final String error, _) => error,
          (_, _, final TranscodeSlotsSnapshot s) =>
            formatTranscodeSlotsDisplay(s),
          _ => 'Unavailable',
        },
        subtitle: transcode?.isCustom == true
            ? 'Default for this machine: ${transcode!.defaultSlots}'
            : 'How many songs this machine converts at once for clients.',
        trailing: OutlinedButton(
          onPressed: transcodeBusy || transcode == null
              ? null
              : onEditTranscodeSlots,
          child: Text(isSavingTranscodeSlots ? 'Saving…' : 'Edit'),
        ),
      ),
    );

    if (host != null && host.autostartSupported) {
      rows.add(
        InfoRow(
          icon: Icons.restart_alt_rounded,
          label: 'Start at boot',
          value: host.autostartEnabled ? 'Enabled' : 'Disabled',
          isActive: host.autostartEnabled,
          subtitle: 'Bring the server back automatically when this machine '
              'restarts.',
          trailing: isSavingAutostart
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Switch(
                  value: host.autostartEnabled,
                  onChanged: onToggleAutostart,
                ),
        ),
      );
    }

    if (isLoadingHostControls && host == null) {
      rows.insert(
        0,
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    return Section(
      title: 'Configuration',
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const CardDivider(),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Extra note shown when the platform cannot offer start-at-boot at all.
class AutostartUnsupportedNote extends StatelessWidget {
  const AutostartUnsupportedNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Start at boot is not available on this platform. In a container, let '
      'your orchestrator restart Ariami instead.',
      style: AppTheme.meta,
    );
  }
}
