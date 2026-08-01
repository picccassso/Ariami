import 'package:ariami_core/models/connect_models.dart';
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
          final thisDeviceId = connect.thisDevice?.id;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final device in _ordered(connect.devices, thisDeviceId))
                _deviceTile(
                  context,
                  connect: connect,
                  device: device,
                  isThisDevice: device.id == thisDeviceId,
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

/// This device first, then the playing device, then alphabetical — the hub
/// orders by arrival, so rows would otherwise reshuffle between openings.
List<AriamiConnectDevice> _ordered(
  List<AriamiConnectDevice> devices,
  String? thisDeviceId,
) {
  final ordered = [...devices];
  ordered.sort((a, b) {
    if ((a.id == thisDeviceId) != (b.id == thisDeviceId)) {
      return a.id == thisDeviceId ? -1 : 1;
    }
    if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return ordered;
}

/// "Here" only ever means this device: the row for this phone says "play
/// here", every other row says "transfer". Saying "play here" on a remote
/// device's row reads as though it targets the device in your hand — which is
/// exactly backwards.
Widget _deviceTile(
  BuildContext context, {
  required AriamiConnectController connect,
  required AriamiConnectDevice device,
  required bool isThisDevice,
}) {
  final scheme = Theme.of(context).colorScheme;
  return ListTile(
    leading: Icon(_icon(device.type)),
    title: Row(
      children: [
        Flexible(child: Text(device.name, overflow: TextOverflow.ellipsis)),
        if (isThisDevice) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              'This device',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    ),
    subtitle: Text(
      device.isActive
          ? (isThisDevice ? 'Playing on this device' : 'Playing now')
          : isThisDevice
              ? 'Tap to play here'
              : 'Tap to transfer',
    ),
    trailing: device.isActive
        ? Icon(Icons.graphic_eq_rounded, color: scheme.primary)
        : const Icon(Icons.chevron_right_rounded),
    onTap: device.isActive || connect.activeDeviceId == null
        ? null
        : () => connect.transferTo(device.id),
  );
}

IconData _icon(String type) => switch (type) {
      'tv' => Icons.tv_rounded,
      'desktop' => Icons.computer_rounded,
      _ => Icons.smartphone_rounded,
    };
