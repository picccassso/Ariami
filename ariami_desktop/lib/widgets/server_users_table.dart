import 'package:flutter/material.dart';

import '../models/server_user_row.dart';
import '../utils/date_formatter.dart';

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
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: (isChangingPassword || isDeleting)
                                    ? null
                                    : () => onChangePassword(row),
                                child: const Text('Change Password'),
                              ),
                              const SizedBox(width: 6),
                              TextButton(
                                onPressed: (isChangingPassword ||
                                        isDeleting ||
                                        !canDeleteUser)
                                    ? null
                                    : () => onDeleteUser(row),
                                child: isDeleting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        'Delete User',
                                        style: TextStyle(
                                          color: canDeleteUser
                                              ? Colors.redAccent
                                              : Colors.white38,
                                        ),
                                      ),
                              ),
                            ],
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
