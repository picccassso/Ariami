import 'package:flutter/material.dart';

import '../../models/server_user_row.dart';
import '../server_users_table.dart';
import 'dashboard_keep_alive_tab.dart';

class DashboardUsersTab extends StatelessWidget {
  const DashboardUsersTab({
    super.key,
    required this.isLoadingServerUsers,
    required this.serverUsersError,
    required this.serverUserRows,
    required this.hasOwnerAccount,
    required this.isCreatingUser,
    required this.isChangingPassword,
    required this.deletingUserIds,
    required this.onCreateUser,
    required this.onChangePassword,
    required this.onDeleteUser,
    required this.onOpenOwnerSetup,
  });

  final bool isLoadingServerUsers;
  final String? serverUsersError;
  final List<ServerUserRow> serverUserRows;
  final bool hasOwnerAccount;
  final bool isCreatingUser;
  final bool isChangingPassword;
  final Set<String> deletingUserIds;
  final VoidCallback onCreateUser;
  final void Function(ServerUserRow row) onChangePassword;
  final void Function(ServerUserRow row) onDeleteUser;
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
          Row(
            children: [
              const Expanded(
                child: Text('Registered Users', style: _sectionTitleStyle),
              ),
              OutlinedButton.icon(
                onPressed: isCreatingUser ? null : onCreateUser,
                icon: isCreatingUser
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add User'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ServerUsersTable(
                isLoading: isLoadingServerUsers,
                errorMessage: serverUsersError,
                rows: serverUserRows,
                ownerActionsEnabled: hasOwnerAccount,
                isChangingPassword: isChangingPassword,
                deletingUserIds: deletingUserIds,
                onChangePassword: onChangePassword,
                onDeleteUser: onDeleteUser,
                onSetUpOwner: onOpenOwnerSetup,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
