import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';
import 'dashboard_keep_alive_tab.dart';
import 'owner_access_error_panel.dart';

class DashboardUsersTab extends StatelessWidget {
  const DashboardUsersTab({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.error,
    required this.showOwnerSignInCta,
    required this.onSignInAsOwner,
    required this.isCreatingUser,
    required this.isChangingPassword,
    required this.deletingUserIds,
    required this.onCreateUser,
    required this.onChangePassword,
    required this.onDeleteUser,
  });

  final List<ServerUserRow> rows;
  final bool isLoading;
  final String? error;
  final bool showOwnerSignInCta;
  final VoidCallback? onSignInAsOwner;
  final bool isCreatingUser;
  final bool isChangingPassword;
  final Set<String> deletingUserIds;
  final VoidCallback onCreateUser;
  final ValueChanged<ServerUserRow> onChangePassword;
  final ValueChanged<ServerUserRow> onDeleteUser;

  @override
  Widget build(BuildContext context) {
    return DashboardKeepAliveTab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Text(
                'Registered Users',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              OutlinedButton.icon(
                onPressed: isCreatingUser || isLoading || error != null
                    ? null
                    : onCreateUser,
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
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.surfaceBlack,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            padding: const EdgeInsets.all(16),
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (error != null) {
      if (showOwnerSignInCta && onSignInAsOwner != null) {
        return OwnerAccessErrorPanel(
          message: error!,
          onSignInAsOwner: onSignInAsOwner!,
        );
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
      );
    }

    if (rows.isEmpty) {
      return const Text(
        'No registered users yet.',
        style: TextStyle(color: Colors.white70),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('User')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Created')),
                DataColumn(label: Text('Connected Devices')),
                DataColumn(label: Text('Actions')),
              ],
              rows: rows.map((row) {
                return DataRow(
                  cells: [
                    DataCell(Text(row.username)),
                    DataCell(
                      Text(
                        row.isAdmin ? 'Admin' : 'User',
                        style: TextStyle(
                          color: row.isAdmin ? Colors.orange.shade200 : null,
                          fontWeight:
                              row.isAdmin ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    DataCell(Text(_formatDateTime(row.createdAt))),
                    DataCell(Text('${row.connectedDeviceCount}')),
                    DataCell(
                      _UserActionsButton(
                        row: row,
                        isChangingPassword: isChangingPassword,
                        isDeleting: deletingUserIds.contains(row.userId),
                        canDeleteUser: !(row.isAdmin && rows.length == 1),
                        onChangePassword: onChangePassword,
                        onDeleteUser: onDeleteUser,
                      ),
                    ),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
        );
      },
    );
  }
}

enum _UserAction {
  changePassword,
  deleteUser,
}

class _UserActionsButton extends StatelessWidget {
  const _UserActionsButton({
    required this.row,
    required this.isChangingPassword,
    required this.isDeleting,
    required this.canDeleteUser,
    required this.onChangePassword,
    required this.onDeleteUser,
  });

  final ServerUserRow row;
  final bool isChangingPassword;
  final bool isDeleting;
  final bool canDeleteUser;
  final ValueChanged<ServerUserRow> onChangePassword;
  final ValueChanged<ServerUserRow> onDeleteUser;

  @override
  Widget build(BuildContext context) {
    final canChangePassword = !isChangingPassword && !isDeleting;
    final canDelete = canChangePassword && canDeleteUser;
    return PopupMenuButton<_UserAction>(
      enabled: canChangePassword || canDelete,
      tooltip: 'User actions',
      onSelected: (action) {
        switch (action) {
          case _UserAction.changePassword:
            if (canChangePassword) onChangePassword(row);
            break;
          case _UserAction.deleteUser:
            if (canDelete) onDeleteUser(row);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _UserAction.changePassword,
          enabled: canChangePassword,
          child: const Text('Change Password'),
        ),
        PopupMenuItem(
          value: _UserAction.deleteUser,
          enabled: canDelete,
          child: Text(
            'Delete User',
            style: TextStyle(
              color: canDelete ? Colors.redAccent : Colors.white38,
            ),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDeleting) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              const Text('Deleting...'),
            ] else ...[
              const Text(
                'Actions',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}
