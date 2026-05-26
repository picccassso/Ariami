import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import 'package:flutter/material.dart';

import 'dashboard_keep_alive_tab.dart';
import 'server_info_card.dart';
import 'transcode_slots_section.dart';

class DashboardServerTab extends StatelessWidget {
  const DashboardServerTab({
    super.key,
    required this.lanServer,
    required this.tailscaleServer,
    required this.lastUpdatedLabel,
    required this.isRefreshingAddresses,
    required this.onRefreshAddresses,
    required this.isAdmin,
    required this.transcodeSlotsSnapshot,
    required this.isLoadingTranscodeSlots,
    required this.isSavingTranscodeSlots,
    required this.transcodeSlotsError,
    required this.onEditTranscodeSlots,
  });

  final String? lanServer;
  final String? tailscaleServer;
  final String? lastUpdatedLabel;
  final bool isRefreshingAddresses;
  final VoidCallback onRefreshAddresses;
  final bool isAdmin;
  final TranscodeSlotsSnapshot? transcodeSlotsSnapshot;
  final bool isLoadingTranscodeSlots;
  final bool isSavingTranscodeSlots;
  final String? transcodeSlotsError;
  final VoidCallback onEditTranscodeSlots;

  @override
  Widget build(BuildContext context) {
    return DashboardKeepAliveTab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServerInfoCard(
            lanServer: lanServer,
            tailscaleServer: tailscaleServer,
            lastUpdatedLabel: lastUpdatedLabel,
            isRefreshing: isRefreshingAddresses,
            onRefreshAddresses: onRefreshAddresses,
          ),
          if (isAdmin) ...[
            const SizedBox(height: 48),
            TranscodeSlotsSection(
              snapshot: transcodeSlotsSnapshot,
              isLoading: isLoadingTranscodeSlots || isSavingTranscodeSlots,
              error: transcodeSlotsError,
              onEdit: onEditTranscodeSlots,
            ),
          ],
        ],
      ),
    );
  }
}
