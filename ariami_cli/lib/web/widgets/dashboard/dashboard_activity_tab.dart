import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import 'connected_clients_section.dart';
import 'dashboard_keep_alive_tab.dart';
import 'user_activity_section.dart';

class DashboardActivityTab extends StatelessWidget {
  const DashboardActivityTab({
    super.key,
    required this.userActivityRows,
    required this.isLoadingUserActivity,
    required this.userActivityError,
    required this.userActivityOwnerForbidden,
    required this.onSignInAsOwner,
    required this.connectedClientRows,
    required this.isLoadingConnectedClients,
    required this.isChangingPassword,
    required this.connectedClientsError,
    required this.connectedClientsOwnerForbidden,
    required this.kickingDeviceIds,
    required this.onKick,
    required this.onChangePassword,
    required this.onChangePasswordForUser,
    required this.formatClientTime,
    required this.formatDeviceLabel,
  });

  final List<UserActivityRow> userActivityRows;
  final bool isLoadingUserActivity;
  final String? userActivityError;
  final bool userActivityOwnerForbidden;
  final VoidCallback? onSignInAsOwner;
  final List<ConnectedClientRow> connectedClientRows;
  final bool isLoadingConnectedClients;
  final bool isChangingPassword;
  final String? connectedClientsError;
  final bool connectedClientsOwnerForbidden;
  final Set<String> kickingDeviceIds;
  final ValueChanged<ConnectedClientRow> onKick;
  final VoidCallback onChangePassword;
  final ValueChanged<String?> onChangePasswordForUser;
  final String Function(DateTime?) formatClientTime;
  final String Function(ConnectedClientRow) formatDeviceLabel;

  @override
  Widget build(BuildContext context) {
    return DashboardKeepAliveTab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserActivitySection(
            rows: userActivityRows,
            isLoading: isLoadingUserActivity,
            error: userActivityError,
            showOwnerSignInCta: userActivityOwnerForbidden,
            onSignInAsOwner: onSignInAsOwner,
          ),
          const SizedBox(height: 48),
          ConnectedClientsSection(
            clients: connectedClientRows,
            isLoading: isLoadingConnectedClients,
            isChangingPassword: isChangingPassword,
            error: connectedClientsError,
            showOwnerSignInCta: connectedClientsOwnerForbidden,
            onSignInAsOwner: onSignInAsOwner,
            kickingDeviceIds: kickingDeviceIds,
            onKick: onKick,
            onChangePassword: onChangePassword,
            onChangePasswordForUser: onChangePasswordForUser,
            formatClientTime: formatClientTime,
            formatDeviceLabel: formatDeviceLabel,
          ),
        ],
      ),
    );
  }
}
