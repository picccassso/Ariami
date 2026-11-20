import 'package:ariami_core/models/connect_models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ariami_connect_controller.dart';
import '../services/audio_controller.dart';
import '../services/player_host.dart';
import '../theme/player_theme.dart';

Future<void> showAriamiConnectSheet(BuildContext context) {
  final connect = context.read<AriamiConnectController>();
  AudioController? audio;
  try {
    audio = context.read<AudioController>();
  } catch (_) {}

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: connect),
        if (audio != null) ChangeNotifierProvider.value(value: audio),
      ],
      child: const _AriamiConnectSheet(),
    ),
  );
}

class AriamiConnectButton extends StatelessWidget {
  const AriamiConnectButton({super.key});

  @override
  Widget build(BuildContext context) {
    final connect = context.watch<AriamiConnectController>();
    AudioController? audio;
    try {
      audio = context.watch<AudioController>();
    } catch (_) {}
    final isCast = audio?.isCastActive ?? false;
    final active = connect.activeDevice;
    final scheme = Theme.of(context).colorScheme;
    final iconColor = (isCast || connect.devices.length > 1)
        ? scheme.secondary
        : context.colors.textSecondary;

    final remoteCast = audio?.remoteCastDeviceName;
    final tooltip = isCast
        ? 'Playing on ${audio?.castDeviceName ?? 'Google Cast'}'
        : (active == null
            ? 'Ariami Connect'
            : remoteCast != null
                ? 'Playing on $remoteCast via ${active.name}'
                : 'Playing on ${active.name}');

    final iconData = isCast || remoteCast != null
        ? Icons.cast_connected_rounded
        : (active?.type == 'tv'
            ? Icons.tv_rounded
            : Icons.speaker_group_rounded);

    return Tooltip(
      message: tooltip,
      child: IconButton(
        iconSize: 20,
        color: iconColor,
        onPressed: () => showAriamiConnectSheet(context),
        icon: Icon(iconData),
      ),
    );
  }
}

class _AriamiConnectSheet extends StatefulWidget {
  const _AriamiConnectSheet();

  @override
  State<_AriamiConnectSheet> createState() => _AriamiConnectSheetState();
}

class _AriamiConnectSheetState extends State<_AriamiConnectSheet> {
  AudioController? _audio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _audio = context.read<AudioController>();
    } catch (_) {
      _audio = null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _audio != null && !_audio!.isCastActive) {
        _audio!.castService?.startDiscovery();
      }
    });
  }

  @override
  void dispose() {
    _audio?.castService?.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connect = context.watch<AriamiConnectController>();
    AudioController? audio;
    try {
      audio = context.watch<AudioController>();
    } catch (_) {}
    final castService = audio?.castService;
    final (thisDevice, others) =
        _split(connect.devices, connect.thisDevice?.id);
    final castDevices = castService?.devices ?? const <PlayerCastDevice>[];
    final remoteCast = audio?.remoteCastDeviceName?.trim().toLowerCase();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ariami Connect',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              castService == null
                  ? 'Move playback between your signed-in devices.'
                  : 'Move playback between your signed-in devices or cast to Google Cast speakers & displays.',
              style: TextStyle(color: context.colors.textSecondary),
            ),
            if (!connect.isConnected) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Reconnecting to Ariami Connect…'),
            ] else if (connect.devices.isEmpty &&
                castDevices.isEmpty &&
                !(audio?.isCastActive ?? false)) ...[
              const SizedBox(height: 20),
              const Text('No playback devices are online.'),
            ] else ...[
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (audio != null && audio.isCastActive) ...[
                        _ActiveCastCard(audio: audio),
                        const SizedBox(height: 16),
                      ],
                      if (thisDevice != null)
                        _DeviceRow(device: thisDevice, isThisComputer: true),
                      if (others.isNotEmpty) ...[
                        if (thisDevice != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'OTHER DEVICES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                        for (final device in others)
                          _DeviceRow(device: device, isThisComputer: false),
                      ],
                      if (audio != null && castService != null) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'GOOGLE CAST',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: context.colors.textSecondary,
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () {
                                castService.stopDiscovery();
                                castService.startDiscovery();
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 14),
                              label: Text(
                                castService.isDiscoveryActive
                                    ? 'Scanning…'
                                    : 'Scan',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (castDevices.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              castService.isDiscoveryActive
                                  ? 'Searching for Google Cast devices on your Wi-Fi…'
                                  : 'No Google Cast devices found on your Wi-Fi network.',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          )
                        else
                          for (final device in castDevices)
                            _CastDeviceRow(
                              device: device,
                              isCurrent: audio.isCastActive &&
                                  audio.castDeviceName == device.name,
                              castingFrom: remoteCast != null &&
                                      device.name.trim().toLowerCase() ==
                                          remoteCast
                                  ? audio.remoteDeviceName
                                  : null,
                              audio: audio,
                            ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (connect.errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: connect.errorMessage!),
            ],
          ],
        ),
      ),
    );
  }

  static (AriamiConnectDevice?, List<AriamiConnectDevice>) _split(
    List<AriamiConnectDevice> devices,
    String? thisDeviceId,
  ) {
    AriamiConnectDevice? mine;
    final others = <AriamiConnectDevice>[];
    for (final device in devices) {
      if (device.id == thisDeviceId) {
        mine = device;
      } else {
        others.add(device);
      }
    }
    others.sort((a, b) => a.isActive != b.isActive
        ? (a.isActive ? -1 : 1)
        : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return (mine, others);
  }
}

class _ActiveCastCard extends StatelessWidget {
  const _ActiveCastCard({required this.audio});
  final AudioController audio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cast_connected_rounded,
                  color: scheme.secondary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audio.castDeviceName ?? 'Google Cast',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Casting from Ariami',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => audio.stopCastingAndResumeLocal(),
                child: const Text('Disconnect'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CastDeviceRow extends StatelessWidget {
  const _CastDeviceRow({
    required this.device,
    required this.isCurrent,
    required this.audio,
    this.castingFrom,
  });

  final PlayerCastDevice device;
  final bool isCurrent;
  final AudioController? audio;

  /// The Connect device currently casting here, when it isn't this computer.
  final String? castingFrom;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        child: Icon(Icons.cast_rounded),
      ),
      title: Text(device.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(isCurrent
          ? 'Connected'
          : castingFrom != null
              ? 'Casting from $castingFrom'
              : 'Google Cast speaker / TV'),
      trailing: isCurrent || castingFrom != null
          ? Icon(Icons.graphic_eq_rounded,
              color: Theme.of(context).colorScheme.secondary)
          : FilledButton.tonal(
              onPressed: audio == null
                  ? null
                  : () => audio!.startCastingToDevice(device),
              child: const Text('Cast'),
            ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.isThisComputer});

  final AriamiConnectDevice device;
  final bool isThisComputer;

  @override
  Widget build(BuildContext context) {
    final connect = context.watch<AriamiConnectController>();
    final reconnecting =
        !device.isActive && device.id == connect.activeDeviceId;
    String? castingTo;
    if (device.isActive && !isThisComputer) {
      try {
        castingTo = context.watch<AudioController>().remoteCastDeviceName;
      } catch (_) {}
    }
    final isWeb = device.type == 'web';
    final thisDeviceLabel = isWeb ? 'this browser' : 'this computer';
    final playingHereText =
        isWeb ? 'Playing in this browser' : 'Playing on this computer';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(_iconFor(device.type))),
      title: Row(
        children: [
          Flexible(
            child: Text(device.name, overflow: TextOverflow.ellipsis),
          ),
          if (isThisComputer) ...[
            const SizedBox(width: 8),
            _ThisDeviceBadge(isWeb: isWeb),
          ],
        ],
      ),
      subtitle: Text(
        device.isActive
            ? (isThisComputer
                ? playingHereText
                : castingTo != null
                    ? 'Casting to $castingTo'
                    : 'Playing now')
            : reconnecting
                ? 'Reconnecting…'
                : 'Available',
      ),
      trailing: device.isActive
          ? Icon(Icons.graphic_eq_rounded,
              color: Theme.of(context).colorScheme.secondary)
          : Tooltip(
              message: isThisComputer
                  ? 'Move playback to $thisDeviceLabel'
                  : 'Move playback to ${device.name}',
              child: FilledButton.tonal(
                onPressed: connect.activeDeviceId == null
                    ? null
                    : () => connect.transferTo(device.id),
                child: Text(isThisComputer ? 'Play here' : 'Transfer'),
              ),
            ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
        'web' => Icons.language_rounded,
        'tv' => Icons.tv_rounded,
        'mobile' => Icons.smartphone_rounded,
        _ => Icons.computer_rounded,
      };
}

class _ThisDeviceBadge extends StatelessWidget {
  const _ThisDeviceBadge({required this.isWeb});

  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.colors.border),
      ),
      child: Text(
        isWeb ? 'This browser' : 'This computer',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(message, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
