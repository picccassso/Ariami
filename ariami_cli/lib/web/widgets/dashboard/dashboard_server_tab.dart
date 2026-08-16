import 'package:ariami_core/models/host_controls.dart';
import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/layout.dart';
import 'dashboard_keep_alive_tab.dart';
import 'server_actions_section.dart';
import 'server_configuration_section.dart';
import 'server_connection_section.dart';
import 'tv_license_section.dart';

/// Everything about the server itself: how clients reach it, how it is
/// configured, the actions an owner takes on it, and how to reset it.
///
/// Laid out to match Ariami Desktop's Server tab so the two dashboards teach
/// the same thing.
class DashboardServerTab extends StatelessWidget {
  const DashboardServerTab({
    super.key,
    required this.lanServer,
    required this.tailscaleServer,
    required this.lastUpdatedLabel,
    required this.isRefreshingAddresses,
    required this.onRefreshAddresses,
    required this.isAdmin,
    required this.apiClient,
    required this.transcodeSlotsSnapshot,
    required this.isLoadingTranscodeSlots,
    required this.isSavingTranscodeSlots,
    required this.transcodeSlotsError,
    required this.onEditTranscodeSlots,
    required this.hostControls,
    required this.isLoadingHostControls,
    required this.isSavingAutostart,
    required this.onToggleAutostart,
    required this.onChangeMusicFolder,
    required this.isScanning,
    required this.onShowQrCode,
    required this.onRescanLibrary,
    required this.onResetAriami,
  });

  final String? lanServer;
  final String? tailscaleServer;
  final String? lastUpdatedLabel;
  final bool isRefreshingAddresses;
  final VoidCallback onRefreshAddresses;
  final bool isAdmin;
  final WebApiClient apiClient;

  final TranscodeSlotsSnapshot? transcodeSlotsSnapshot;
  final bool isLoadingTranscodeSlots;
  final bool isSavingTranscodeSlots;
  final String? transcodeSlotsError;
  final VoidCallback onEditTranscodeSlots;

  final HostControlsSnapshot? hostControls;
  final bool isLoadingHostControls;
  final bool isSavingAutostart;
  final ValueChanged<bool> onToggleAutostart;
  final VoidCallback onChangeMusicFolder;

  final bool isScanning;
  final VoidCallback onShowQrCode;
  final VoidCallback onRescanLibrary;
  final VoidCallback onResetAriami;

  @override
  Widget build(BuildContext context) {
    final gap = AppLayout.sectionGap(AppLayout.of(context));
    final host = hostControls;

    return DashboardKeepAliveTab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServerConnectionSection(
            lanServer: lanServer,
            tailscaleServer: tailscaleServer,
            lastUpdatedLabel: lastUpdatedLabel,
            isRefreshing: isRefreshingAddresses,
            onRefreshAddresses: onRefreshAddresses,
          ),
          if (isAdmin) ...[
            SizedBox(height: gap),
            ServerConfigurationSection(
              hostControls: host,
              isLoadingHostControls: isLoadingHostControls,
              isSavingAutostart: isSavingAutostart,
              onToggleAutostart: onToggleAutostart,
              onChangeMusicFolder: onChangeMusicFolder,
              transcodeSlotsSnapshot: transcodeSlotsSnapshot,
              isLoadingTranscodeSlots: isLoadingTranscodeSlots,
              isSavingTranscodeSlots: isSavingTranscodeSlots,
              transcodeSlotsError: transcodeSlotsError,
              onEditTranscodeSlots: onEditTranscodeSlots,
            ),
            if (host != null && !host.autostartSupported) ...[
              const SizedBox(height: 10),
              const AutostartUnsupportedNote(),
            ],
            SizedBox(height: gap),
            ServerActionsSection(
              isScanning: isScanning,
              onShowQrCode: onShowQrCode,
              onRescanLibrary: onRescanLibrary,
            ),
            SizedBox(height: gap),
            TvLicenseSection(apiClient: apiClient),
            SizedBox(height: gap),
            DangerZoneSection(
              enabled: host?.resetSupported ?? false,
              onResetAriami: onResetAriami,
            ),
          ],
        ],
      ),
    );
  }
}
