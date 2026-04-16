import 'package:flutter/material.dart';

import '../models/connected_client_row.dart';
import '../utils/date_formatter.dart';

/// Table of connected users/devices with admin kick actions.
class ConnectedUsersTable extends StatelessWidget {
  const ConnectedUsersTable({
    super.key,
    required this.isLoading,
    required this.errorMessage,
    required this.rows,
    required this.ownerActionsEnabled,
    required this.kickingDeviceIds,
    required this.onKick,
    required this.onSetUpOwner,
  });

  final bool isLoading;
  final String? errorMessage;
  final List<ConnectedClientRow> rows;
  final bool ownerActionsEnabled;
  final Set<String> kickingDeviceIds;
  final void Function(ConnectedClientRow row) onKick;
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
          'No connected devices.',
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
                DataColumn(label: Text('Device')),
                DataColumn(label: Text('Connected')),
                DataColumn(label: Text('Last Heartbeat')),
                DataColumn(label: Text('Actions')),
              ],
              rows: rows.map((row) {
                final isKicking = kickingDeviceIds.contains(row.deviceId);
                final userLabel =
                    row.username ?? row.userId ?? 'Unauthenticated';
                return DataRow(cells: [
                  DataCell(Text(userLabel)),
                  DataCell(Text(
                      ConnectedClientFormatting.formatConnectedDeviceLabel(
                          row))),
                  DataCell(Text(formatDashboardDateTime(row.connectedAt))),
                  DataCell(Text(formatDashboardDateTime(row.lastHeartbeat))),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!ownerActionsEnabled)
                          TextButton(
                            onPressed: onSetUpOwner,
                            child: const Text('Set Up Owner'),
                          )
                        else ...[
                          TextButton(
                            onPressed: isKicking ? null : () => onKick(row),
                            child: isKicking
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Kick'),
                          ),
                        ],
                      ],
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
