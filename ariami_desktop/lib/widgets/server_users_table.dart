import 'package:flutter/material.dart';

import '../models/server_user_row.dart';
import '../utils/date_formatter.dart';

enum _UserActionMenuItem {
  changePassword,
  deleteUser,
}

/// Table of all registered server users with admin account actions.
class ServerUsersTable extends StatelessWidget {
  const ServerUsersTable({
    super.key,
    required this.isLoading,
    required this.errorMessage,
    required this.rows,
    required this.ownerActionsEnabled,
    required this.isChangingPassword,
    required this.deletingUserIds,
    required this.onChangePassword,
    required this.onDeleteUser,
    required this.onSetUpOwner,
  });

  final bool isLoading;
  final String? errorMessage;
  final List<ServerUserRow> rows;
  final bool ownerActionsEnabled;
  final bool isChangingPassword;
  final Set<String> deletingUserIds;
  final void Function(ServerUserRow row) onChangePassword;
  final void Function(ServerUserRow row) onDeleteUser;
  final VoidCallback onSetUpOwner;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Text(
          errorMessage!,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }

    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: const Text(
          'No registered users yet.',
          style: TextStyle(color: Colors.white70),
        ),
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
                final isDeleting = deletingUserIds.contains(row.userId);
                final canDeleteUser = !(row.isAdmin && rows.length == 1);
                return DataRow(cells: [
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
                  DataCell(Text(formatDashboardDateTime(row.createdAt))),
                  DataCell(Text(row.connectedDeviceCount.toString())),
                  DataCell(
                    ownerActionsEnabled
                        ? _UserActionsButton(
                            row: row,
                            isChangingPassword: isChangingPassword,
                            isDeleting: isDeleting,
                            canDeleteUser: canDeleteUser,
                            onChangePassword: onChangePassword,
                            onDeleteUser: onDeleteUser,
                          )
                        : TextButton(
                            onPressed: onSetUpOwner,
                            child: const Text('Set Up Owner'),
                          ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _UserActionsButton extends StatefulWidget {
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
  final void Function(ServerUserRow row) onChangePassword;
  final void Function(ServerUserRow row) onDeleteUser;

  @override
  State<_UserActionsButton> createState() => _UserActionsButtonState();
}

class _UserActionsButtonState extends State<_UserActionsButton> {
  final GlobalKey<PopupMenuButtonState<_UserActionMenuItem>> _menuKey =
      GlobalKey<PopupMenuButtonState<_UserActionMenuItem>>();

  bool get _canChangePassword =>
      !widget.isChangingPassword && !widget.isDeleting;

  bool get _canDeleteUser =>
      !widget.isChangingPassword && !widget.isDeleting && widget.canDeleteUser;

  bool get _isEnabled => _canChangePassword || _canDeleteUser;

  void _onSelected(_UserActionMenuItem value) {
    switch (value) {
      case _UserActionMenuItem.changePassword:
        if (_canChangePassword) {
          widget.onChangePassword(widget.row);
        }
        break;
      case _UserActionMenuItem.deleteUser:
        if (_canDeleteUser) {
          widget.onDeleteUser(widget.row);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = _isEnabled ? Colors.white : Colors.white38;
    return PopupMenuButton<_UserActionMenuItem>(
      key: _menuKey,
      enabled: _isEnabled,
      tooltip: 'User actions',
      onSelected: _onSelected,
      itemBuilder: (context) => <PopupMenuEntry<_UserActionMenuItem>>[
        PopupMenuItem<_UserActionMenuItem>(
          value: _UserActionMenuItem.changePassword,
          enabled: _canChangePassword,
          child: const Text('Change Password'),
        ),
        PopupMenuItem<_UserActionMenuItem>(
          value: _UserActionMenuItem.deleteUser,
          enabled: _canDeleteUser,
          child: Text(
            'Delete User',
            style: TextStyle(
              color: _canDeleteUser ? Colors.redAccent : Colors.white38,
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
            if (widget.isDeleting) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              const Text('Deleting...'),
            ] else ...[
              Text(
                'Actions',
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 18, color: foreground),
            ],
          ],
        ),
      ),
    );
  }
}
