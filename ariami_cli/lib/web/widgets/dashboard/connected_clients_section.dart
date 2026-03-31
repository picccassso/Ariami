import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';

class ConnectedClientsSection extends StatelessWidget {
  const ConnectedClientsSection({
    super.key,
    required this.clients,
    required this.isLoading,
    required this.isChangingPassword,
    required this.error,
    required this.kickingDeviceIds,
    required this.onKick,
    required this.onChangePassword,
    required this.onChangePasswordForUser,
    required this.formatClientTime,
    required this.formatDeviceLabel,
  });

  final List<ConnectedClientRow> clients;
  final bool isLoading;
  final bool isChangingPassword;
  final String? error;
  final Set<String> kickingDeviceIds;
  final ValueChanged<ConnectedClientRow> onKick;
  final VoidCallback onChangePassword;
  final ValueChanged<String?> onChangePasswordForUser;
  final String Function(DateTime?) formatClientTime;
  final String Function(ConnectedClientRow) formatDeviceLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGrey),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'CONNECTED USERS & DEVICES',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textSecondary,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: isChangingPassword ? null : onChangePassword,
                icon: isChangingPassword
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.lock_reset_rounded, size: 18),
                label: const Text('CHANGE PASSWORD'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else if (error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(
                error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            )
          else if (clients.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No connected devices.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                dataTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
                columns: const [
                  DataColumn(label: Text('USER')),
                  DataColumn(label: Text('DEVICE')),
                  DataColumn(label: Text('CONNECTED')),
                  DataColumn(label: Text('LAST HEARTBEAT')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: clients.map((client) {
                  final isKicking = kickingDeviceIds.contains(client.deviceId);
                  final userLabel =
                      client.username ?? client.userId ?? 'Unauthenticated';
                  return DataRow(
                    cells: [
                      DataCell(Text(userLabel)),
                      DataCell(Text(formatDeviceLabel(client))),
                      DataCell(Text(formatClientTime(client.connectedAt))),
                      DataCell(Text(formatClientTime(client.lastHeartbeat))),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed:
                                  isKicking ? null : () => onKick(client),
                              child: isKicking
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Kick'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: isChangingPassword
                                  ? null
                                  : () => onChangePasswordForUser(
                                      client.username,
                                    ),
                              child: const Text('Change Password'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
