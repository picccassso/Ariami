import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/cast/chrome_cast_service.dart';
import '../../services/playback_manager.dart';
import '../common/mini_player_aware_bottom_sheet.dart';

/// Cast button for the full player top bar with connected/disconnected icons.
class PlayerCastButton extends StatefulWidget {
  final PlaybackManager playbackManager;

  const PlayerCastButton({
    super.key,
    required this.playbackManager,
  });

  @override
  State<PlayerCastButton> createState() => _PlayerCastButtonState();
}

class _PlayerCastButtonState extends State<PlayerCastButton> {
  final ChromeCastService _castService = ChromeCastService();

  @override
  void initState() {
    super.initState();
    _castService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_castService, widget.playbackManager]),
      builder: (context, _) {
        final isConnected = _castService.isConnected;
        final isBusy = _castService.isConnecting ||
            widget.playbackManager.isCastTransitionInProgress;

        return IconButton(
          icon: Icon(
            isConnected ? Icons.cast_connected_rounded : LucideIcons.cast,
            color: isConnected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.9),
          ),
          onPressed:
              _castService.isSupportedPlatform && !isBusy ? _onPressed : null,
          tooltip: isConnected ? 'Disconnect Chromecast' : 'Connect Chromecast',
        );
      },
    );
  }

  Future<void> _onPressed() async {
    if (_castService.isConnected) {
      await _showConnectedActions();
      return;
    }
    await _showDevicePicker();
  }

  Future<void> _showDevicePicker() async {
    await _castService.startDiscovery();
    if (!mounted) return;

    await showAriamiSheet<void>(
      context: context,
      header: const AriamiSheetHeader(
        title: 'Cast To Device',
        subtitle: 'Pick a Chromecast on your network',
      ),
      child: AnimatedBuilder(
        animation: _castService,
        builder: (context, _) {
          final devices = _castService.devices;

          if (devices.isEmpty) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Searching for Chromecast devices...'),
                  ),
                ],
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final device in devices)
                ListTile(
                  leading: const Icon(LucideIcons.speaker),
                  title: Text(device.friendlyName),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _connectAndSync(device);
                  },
                ),
            ],
          );
        },
      ),
    );

    await _castService.stopDiscovery();
  }

  Future<void> _connectAndSync(GoogleCastDevice device) async {
    try {
      await widget.playbackManager.startCastingToDevice(device);
    } catch (_) {
      // Chromecast connection failed silently.
    }
  }

  Future<void> _showConnectedActions() async {
    final deviceName = _castService.connectedDeviceName ?? 'Chromecast';
    await showAriamiSheet<void>(
      context: context,
      header: AriamiSheetHeader(
        title: deviceName,
        subtitle: 'Audio is being cast from Ariami',
        leading: Icon(
          Icons.cast_connected_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      items: [
        ListTile(
          leading: const Icon(Icons.cast),
          title: const Text('Disconnect'),
          onTap: () async {
            Navigator.of(context).pop();
            await widget.playbackManager.stopCastingAndResumeLocal();
          },
        ),
      ],
    );
  }
}
