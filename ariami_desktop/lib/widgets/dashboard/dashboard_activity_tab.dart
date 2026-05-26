import 'package:ariami_core/ariami_core.dart';
import 'package:flutter/material.dart';

import '../../models/connected_client_row.dart';
import '../connected_users_table.dart';
import '../user_activity_table.dart';
import 'dashboard_keep_alive_tab.dart';

class DashboardActivityTab extends StatelessWidget {
  const DashboardActivityTab({
    super.key,
    required this.isLoadingUserActivity,
    required this.userActivityError,
    required this.userActivityRows,
    required this.isLoadingConnectedRows,
    required this.connectedRowsError,
    required this.connectedClientRows,
    required this.hasOwnerAccount,
    required this.kickingDeviceIds,
    required this.onKick,
    required this.onOpenOwnerSetup,
  });

  final bool isLoadingUserActivity;
  final String? userActivityError;
  final List<UserActivityRow> userActivityRows;
  final bool isLoadingConnectedRows;
  final String? connectedRowsError;
  final List<ConnectedClientRow> connectedClientRows;
  final bool hasOwnerAccount;
  final Set<String> kickingDeviceIds;
  final void Function(ConnectedClientRow row) onKick;
  final VoidCallback onOpenOwnerSetup;

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
          const Text('User Activity', style: _sectionTitleStyle),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: UserActivityTable(
                isLoading: isLoadingUserActivity,
                errorMessage: userActivityError,
                rows: userActivityRows,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text('Connected Users & Devices', style: _sectionTitleStyle),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConnectedUsersTable(
                isLoading: isLoadingConnectedRows,
                errorMessage: connectedRowsError,
                rows: connectedClientRows,
                ownerActionsEnabled: hasOwnerAccount,
                kickingDeviceIds: kickingDeviceIds,
                onKick: onKick,
                onSetUpOwner: onOpenOwnerSetup,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
