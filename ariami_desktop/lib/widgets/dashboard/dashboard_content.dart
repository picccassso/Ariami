import 'package:ariami_core/ariami_core.dart';
import 'package:flutter/material.dart';

import '../../models/connected_client_row.dart';
import '../../models/server_user_row.dart';
import 'dashboard_activity_tab.dart';
import 'dashboard_overview_tab.dart';
import 'dashboard_server_tab.dart';
import 'dashboard_users_tab.dart';

/// Presentational shell for the dashboard tabs.
class DashboardContent extends StatelessWidget {
  const DashboardContent({
    super.key,
    required this.tabController,
    required this.isLoading,
    required this.httpServer,
    required this.connectedClients,
    required this.hasOwnerAccount,
    required this.isLoadingUserActivity,
    required this.userActivityError,
    required this.userActivityRows,
    required this.isLoadingConnectedRows,
    required this.connectedRowsError,
    required this.connectedClientRows,
    required this.kickingDeviceIds,
    required this.isLoadingServerUsers,
    required this.serverUsersError,
    required this.serverUserRows,
    required this.isCreatingUser,
    required this.isChangingPassword,
    required this.deletingUserIds,
    required this.isTvAccountPickerEnabled,
    required this.onToggleTvAccountPicker,
    required this.musicFolderPath,
    required this.transcodeSlotsSnapshot,
    required this.isSavingTranscodeSlots,
    required this.lanIP,
    required this.tailscaleIP,
    required this.addressRefreshTimeLabel,
    required this.isRefreshingAddresses,
    required this.onToggleServer,
    required this.onOpenOwnerSetup,
    required this.onKick,
    required this.onCreateUser,
    required this.onChangePassword,
    required this.onDeleteUser,
    required this.onEditTranscodeSlots,
    required this.onRefreshAddresses,
    required this.onChangeFolder,
    required this.onShowQr,
    required this.onRescanLibrary,
    required this.onResetAriami,
  });

  final TabController tabController;
  final bool isLoading;
  final AriamiHttpServer httpServer;
  final int connectedClients;
  final bool hasOwnerAccount;
  final bool isLoadingUserActivity;
  final String? userActivityError;
  final List<UserActivityRow> userActivityRows;
  final bool isLoadingConnectedRows;
  final String? connectedRowsError;
  final List<ConnectedClientRow> connectedClientRows;
  final Set<String> kickingDeviceIds;
  final bool isLoadingServerUsers;
  final String? serverUsersError;
  final List<ServerUserRow> serverUserRows;
  final bool isCreatingUser;
  final bool isChangingPassword;
  final Set<String> deletingUserIds;
  final bool isTvAccountPickerEnabled;
  final ValueChanged<bool> onToggleTvAccountPicker;
  final String? musicFolderPath;
  final TranscodeSlotsSnapshot? transcodeSlotsSnapshot;
  final bool isSavingTranscodeSlots;
  final String? lanIP;
  final String? tailscaleIP;
  final String addressRefreshTimeLabel;
  final bool isRefreshingAddresses;
  final VoidCallback onToggleServer;
  final VoidCallback onOpenOwnerSetup;
  final void Function(ConnectedClientRow row) onKick;
  final VoidCallback onCreateUser;
  final void Function(ServerUserRow row) onChangePassword;
  final void Function(ServerUserRow row) onDeleteUser;
  final VoidCallback onEditTranscodeSlots;
  final VoidCallback onRefreshAddresses;
  final VoidCallback onChangeFolder;
  final VoidCallback onShowQr;
  final VoidCallback? onRescanLibrary;
  final VoidCallback onResetAriami;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Activity'),
            Tab(text: 'Users'),
            Tab(text: 'Server'),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : TabBarView(
              controller: tabController,
              children: [
                DashboardOverviewTab(
                  httpServer: httpServer,
                  connectedClients: connectedClients,
                  hasOwnerAccount: hasOwnerAccount,
                  onToggleServer: onToggleServer,
                  onOpenOwnerSetup: onOpenOwnerSetup,
                ),
                DashboardActivityTab(
                  isLoadingUserActivity: isLoadingUserActivity,
                  userActivityError: userActivityError,
                  userActivityRows: userActivityRows,
                  isLoadingConnectedRows: isLoadingConnectedRows,
                  connectedRowsError: connectedRowsError,
                  connectedClientRows: connectedClientRows,
                  hasOwnerAccount: hasOwnerAccount,
                  kickingDeviceIds: kickingDeviceIds,
                  onKick: onKick,
                  onOpenOwnerSetup: onOpenOwnerSetup,
                ),
                DashboardUsersTab(
                  isLoadingServerUsers: isLoadingServerUsers,
                  serverUsersError: serverUsersError,
                  serverUserRows: serverUserRows,
                  hasOwnerAccount: hasOwnerAccount,
                  isCreatingUser: isCreatingUser,
                  isChangingPassword: isChangingPassword,
                  deletingUserIds: deletingUserIds,
                  isTvAccountPickerEnabled: isTvAccountPickerEnabled,
                  onCreateUser: onCreateUser,
                  onChangePassword: onChangePassword,
                  onDeleteUser: onDeleteUser,
                  onOpenOwnerSetup: onOpenOwnerSetup,
                  onToggleTvAccountPicker: onToggleTvAccountPicker,
                ),
                DashboardServerTab(
                  musicFolderPath: musicFolderPath,
                  transcodeSlotsSnapshot: transcodeSlotsSnapshot,
                  isSavingTranscodeSlots: isSavingTranscodeSlots,
                  lanIP: lanIP,
                  tailscaleIP: tailscaleIP,
                  addressRefreshTimeLabel: addressRefreshTimeLabel,
                  isRefreshingAddresses: isRefreshingAddresses,
                  onEditTranscodeSlots: onEditTranscodeSlots,
                  onRefreshAddresses: onRefreshAddresses,
                  onChangeFolder: onChangeFolder,
                  onShowQr: onShowQr,
                  onRescanLibrary: onRescanLibrary,
                  onResetAriami: onResetAriami,
                ),
              ],
            ),
    );
  }
}
