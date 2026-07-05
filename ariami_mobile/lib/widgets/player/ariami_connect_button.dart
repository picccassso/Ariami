import 'package:flutter/material.dart';

import '../../services/ariami_connect_controller.dart';
import '../common/mini_player_aware_bottom_sheet.dart';

class AriamiConnectButton extends StatelessWidget {
  const AriamiConnectButton({super.key});

  @override
  Widget build(BuildContext context) {
    final connect = AriamiConnectController();
    return AnimatedBuilder(
      animation: connect,
      builder: (context, _) => IconButton(
        tooltip: connect.activeDevice == null
            ? 'Ariami Connect'
            : 'Playing on ${connect.activeDevice!.name}',
        onPressed: () => showAriamiConnectPicker(context),
        icon: Icon(
          connect.activeDevice?.type == 'tv'
              ? Icons.tv_rounded
              : Icons.speaker_group_rounded,
          color: connect.devices.length > 1
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
      ),
    );
  }
}

Future<void> showAriamiConnectPicker(BuildContext context) {
  final connect = AriamiConnectController();
  return showAriamiSheet<void>(
    context: context,
    header: const AriamiSheetHeader(
      title: 'Ariami Connect',
      subtitle: 'Move playback between signed-in devices, on LAN or Tailscale.',
    ),
    items: [
      AnimatedBuilder(
        animation: connect,
        builder: (context, _) {
          if (!connect.isConnected) {
            return const ListTile(
              leading: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              title: Text('Reconnecting to Ariami Connect…'),
            );
          }
          if (connect.devices.isEmpty) {
            return const ListTile(
              leading: Icon(Icons.devices_other_rounded),
              title: Text('No playback devices are online'),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final device in connect.devices)
                ListTile(
                  leading: Icon(_icon(device.type)),
                  title: Text(device.name),
                  subtitle: Text(device.isActive
                      ? 'Playing here now'
                      : 'Tap to play here'),
                  trailing: device.isActive
                      ? Icon(Icons.graphic_eq_rounded,
                          color: Theme.of(context).colorScheme.primary)
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: device.isActive || connect.activeDeviceId == null
                      ? null
                      : () => connect.transferTo(device.id),
                ),
              if (connect.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    connect.errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

IconData _icon(String type) => switch (type) {
      'tv' => Icons.tv_rounded,
      'desktop' => Icons.computer_rounded,
      _ => Icons.smartphone_rounded,
    };
