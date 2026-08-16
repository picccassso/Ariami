import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';
import '../../utils/layout.dart';
import '../ui/data_section.dart';
import '../ui/section.dart';
import 'dashboard_keep_alive_tab.dart';

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
    required this.userPickerEnabled,
    required this.isSavingUserPicker,
    required this.onToggleUserPicker,
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

  /// null hides the section (non-admin, or the setting hasn't loaded).
  final bool? userPickerEnabled;
  final bool isSavingUserPicker;
  final ValueChanged<bool> onToggleUserPicker;

  @override
  Widget build(BuildContext context) {
    final gap = AppLayout.sectionGap(AppLayout.of(context));

    return DashboardKeepAliveTab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Section(
            title: 'Accounts',
            description: 'Everyone who can sign in to this server.',
            trailing: OutlinedButton.icon(
              onPressed: isCreatingUser || isLoading || error != null
                  ? null
                  : onCreateUser,
              icon: isCreatingUser
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Add account'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
            child: AppCard(
              child: DataSectionBody(
                isLoading: isLoading,
                error: error,
                showOwnerSignInCta: showOwnerSignInCta,
                onSignInAsOwner: onSignInAsOwner,
                isEmpty: rows.isEmpty,
                emptyMessage: 'No accounts yet.',
                child: AppDataTable(
                  columns: const [
                    DataColumn(label: Text('User')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Created')),
                    DataColumn(label: Text('Devices')),
                    DataColumn(label: Text('')),
                  ],
                  rows: rows.map((row) {
                    return DataRow(
                      cells: [
                        DataCell(Text(
                          row.username,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )),
                        DataCell(_RoleChip(isAdmin: row.isAdmin)),
                        DataCell(Text(
                          _formatDateTime(row.createdAt),
                          style:
                              const TextStyle(color: AppTheme.textSecondary),
                        )),
                        DataCell(Text(
                          '${row.connectedDeviceCount}',
                          style:
                              const TextStyle(color: AppTheme.textSecondary),
                        )),
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
            ),
          ),
          if (userPickerEnabled != null) ...[
            SizedBox(height: gap),
            Section(
              title: 'Sign-in privacy',
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Show account picker on TV sign-in',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Lets Ariami TV list this server\'s accounts on '
                            'its sign-in screen. While enabled, any device on '
                            'your network can see the account names and '
                            'photos (passwords are always required). When '
                            'off, TV users type their username instead.',
                            style: AppTheme.meta,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Switch(
                      value: userPickerEnabled!,
                      onChanged: isSavingUserPicker ? null : onToggleUserPicker,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) {
      return const Text('User', style: TextStyle(color: AppTheme.textSecondary));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.borderStrong),
      ),
      child: const Text(
        'Owner',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
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
      tooltip: 'Account actions',
      position: PopupMenuPosition.under,
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
          child: const Text('Change password'),
        ),
        PopupMenuItem(
          value: _UserAction.deleteUser,
          enabled: canDelete,
          child: Text(
            'Delete account',
            style: TextStyle(
              color: canDelete ? AppTheme.danger : AppTheme.textTertiary,
            ),
          ),
        ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceRaised,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: AppTheme.borderStrong),
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
                const Text('Deleting…'),
              ] else ...[
                const Text(
                  'Manage',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, size: 17),
              ],
            ],
          ),
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
