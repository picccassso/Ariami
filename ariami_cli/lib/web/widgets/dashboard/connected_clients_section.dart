import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';
import '../ui/data_section.dart';
import '../ui/section.dart';

class ConnectedClientsSection extends StatelessWidget {
  const ConnectedClientsSection({
    super.key,
    required this.clients,
    required this.isLoading,
    required this.isChangingPassword,
    required this.error,
    this.showOwnerSignInCta = false,
    this.onSignInAsOwner,
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
  final bool showOwnerSignInCta;
  final VoidCallback? onSignInAsOwner;
  final Set<String> kickingDeviceIds;
  final ValueChanged<ConnectedClientRow> onKick;
  final VoidCallback onChangePassword;
  final ValueChanged<String?> onChangePasswordForUser;
  final String Function(DateTime?) formatClientTime;
  final String Function(ConnectedClientRow) formatDeviceLabel;

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Connected devices',
      description: 'Every device signed in to this server. Kicking one ends '
          'its session immediately.',
      trailing: TextButton.icon(
        onPressed: isChangingPassword ? null : onChangePassword,
        icon: isChangingPassword
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.lock_reset_rounded, size: 17),
        label: const Text('Change a password'),
      ),
      child: AppCard(
        child: DataSectionBody(
          isLoading: isLoading,
          error: error,
          showOwnerSignInCta: showOwnerSignInCta,
          onSignInAsOwner: onSignInAsOwner,
          isEmpty: clients.isEmpty,
          emptyMessage: 'No devices are connected.',
          child: AppDataTable(
            columns: const [
              DataColumn(label: Text('User')),
              DataColumn(label: Text('Device')),
              DataColumn(label: Text('Connected')),
              DataColumn(label: Text('Last heartbeat')),
              DataColumn(label: Text('')),
            ],
            rows: clients.map((client) {
              final isKicking = kickingDeviceIds.contains(client.deviceId);
              return DataRow(
                cells: [
                  DataCell(Text(
                    client.username ?? client.userId ?? 'Not signed in',
                  )),
                  DataCell(Text(formatDeviceLabel(client))),
                  DataCell(Text(
                    formatClientTime(client.connectedAt),
                    style: const TextStyle(color: AppTheme.textSecondary),
                  )),
                  DataCell(Text(
                    formatClientTime(client.lastHeartbeat),
                    style: const TextStyle(color: AppTheme.textSecondary),
                  )),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: isChangingPassword
                              ? null
                              : () => onChangePasswordForUser(client.username),
                          child: const Text('Password'),
                        ),
                        TextButton(
                          onPressed: isKicking ? null : () => onKick(client),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                          ),
                          child: isKicking
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Kick'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(growable: false),
          ),
        ),
      ),
    );
  }
}
