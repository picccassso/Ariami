import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import 'package:flutter/material.dart';

import '../info_card.dart';
import '../transcode_slots_dialog.dart';
import 'dashboard_keep_alive_tab.dart';

class DashboardServerTab extends StatelessWidget {
  const DashboardServerTab({
    super.key,
    required this.musicFolderPath,
    required this.transcodeSlotsSnapshot,
    required this.isSavingTranscodeSlots,
    required this.lanIP,
    required this.tailscaleIP,
    required this.addressRefreshTimeLabel,
    required this.isRefreshingAddresses,
    required this.onEditTranscodeSlots,
    required this.onRefreshAddresses,
    required this.onChangeFolder,
    required this.onShowQr,
    required this.onRescanLibrary,
  });

  final String? musicFolderPath;
  final TranscodeSlotsSnapshot? transcodeSlotsSnapshot;
  final bool isSavingTranscodeSlots;
  final String? lanIP;
  final String? tailscaleIP;
  final String addressRefreshTimeLabel;
  final bool isRefreshingAddresses;
  final VoidCallback onEditTranscodeSlots;
  final VoidCallback onRefreshAddresses;
  final VoidCallback onChangeFolder;
  final VoidCallback onShowQr;
  final VoidCallback? onRescanLibrary;

  static const _sectionTitleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  @override
  Widget build(BuildContext context) {
    return DashboardKeepAliveTab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Configuration', style: _sectionTitleStyle),
          const SizedBox(height: 16),
          InfoCard(
            title: 'Music Folder',
            value: musicFolderPath ?? 'Not configured',
            icon: Icons.folder_rounded,
            isActive: musicFolderPath != null,
          ),
          const SizedBox(height: 12),
          InfoCard(
            title: 'Transcode Slots',
            value: transcodeSlotsSnapshot == null
                ? 'Loading...'
                : formatTranscodeSlotsDisplay(transcodeSlotsSnapshot!),
            icon: Icons.speed_rounded,
            isActive: true,
            subtitle: transcodeSlotsSnapshot?.isCustom == true
                ? 'Default for this device: '
                    '${transcodeSlotsSnapshot!.defaultSlots}'
                : null,
            trailing: TextButton(
              onPressed: transcodeSlotsSnapshot == null || isSavingTranscodeSlots
                  ? null
                  : onEditTranscodeSlots,
              child: Text(isSavingTranscodeSlots ? 'Saving...' : 'Edit'),
            ),
          ),
          const SizedBox(height: 12),
          InfoCard(
            title: 'LAN Address',
            value: lanIP ?? 'Not connected',
            icon: Icons.router_rounded,
            isActive: lanIP != null,
          ),
          const SizedBox(height: 12),
          InfoCard(
            title: 'Tailscale IP',
            value: tailscaleIP ?? 'Not connected',
            icon: Icons.cloud_done_rounded,
            isActive: tailscaleIP != null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  addressRefreshTimeLabel,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: isRefreshingAddresses ? null : onRefreshAddresses,
                icon: isRefreshingAddresses
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  isRefreshingAddresses ? 'Refreshing...' : 'Refresh Addresses',
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text('Quick Actions', style: _sectionTitleStyle),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onChangeFolder,
                  icon: const Icon(Icons.drive_file_move_rounded, size: 20),
                  label: const Text('Change Folder'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF333333)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShowQr,
                  icon: const Icon(Icons.qr_code_rounded, size: 20),
                  label: const Text('Show QR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF333333)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRescanLibrary,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Rescan Library'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF333333)),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
