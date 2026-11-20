import 'package:ariami_core/models/connect_models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ariami_connect_controller.dart';
import '../../services/connection_controller.dart';
import '../../theme/player_theme.dart';
import 'settings_widgets.dart';

class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    final connect = context.watch<AriamiConnectController>();
    final info = connection.serverInfo;
    final deviceName = connect.thisDevice?.name ?? connection.connectDeviceName;
    return SettingsSectionCard(
      title: 'Account & connection',
      subtitle: 'Who you are signed in as, and where your music comes from.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsKeyValueRow('Signed in as', connection.username ?? '—',
              sensitive: true),
          SettingsKeyValueRow('Server', info?.name ?? '—', sensitive: true),
          SettingsKeyValueRow(
              'Address',
              info != null
                  ? (connection.isSameOriginWeb
                      ? info.baseUrl
                      : '${info.host}:${info.port}')
                  : '—',
              sensitive: true),
          SettingsKeyValueRow('Version', info?.version ?? '—'),
          SettingsKeyValueRow(
            'Mode',
            connection.isLocalServer
                ? 'Server + player on this computer'
                : connection.isSameOriginWeb
                    ? 'Connected via web player'
                    : 'Playing from a remote server',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 130,
                  child: Text('Device name',
                      style: TextStyle(
                          color: context.colors.textSecondary, fontSize: 13)),
                ),
                Expanded(
                  child: SensitiveText(deviceName),
                ),
                Tooltip(
                  message: connect.isConnected
                      ? 'How this device appears in Ariami Connect on all '
                          'your devices'
                      : 'Connect to your server to rename this device',
                  child: TextButton.icon(
                    onPressed: connect.isConnected
                        ? () => _renameDevice(context, connect, deviceName)
                        : null,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Rename'),
                  ),
                ),
              ],
            ),
          ),
          if (connection.isLocalServer) ...[
            const SizedBox(height: 8),
            Text(
              'This computer is also the server — manage it from the Server '
              'sections on the left.',
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => connection.disconnect(),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: Text(connection.canChooseDifferentServer
                ? 'Sign out / switch server'
                : 'Sign out'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameDevice(
    BuildContext context,
    AriamiConnectController connect,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename this device'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: kMaxDeviceDisplayNameLength,
            decoration: const InputDecoration(
              labelText: 'Device name',
              hintText: 'e.g. Office Mac',
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    final normalized = normalizeDeviceDisplayName(name);
    if (normalized != null && normalized != currentName) {
      connect.renameThisDevice(normalized);
    }
  }
}
