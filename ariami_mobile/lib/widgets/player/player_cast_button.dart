import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/cast/chrome_cast_service.dart';
import '../../services/playback_manager.dart';

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

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: AnimatedBuilder(
            animation: _castService,
            builder: (context, _) {
              final devices = _castService.devices;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'Cast To Device',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (devices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 28),
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
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: devices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          return ListTile(
                            leading: const Icon(LucideIcons.speaker),
                            title: Text(device.friendlyName),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await _connectAndSync(device);
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );

    await _castService.stopDiscovery();
  }

  Future<void> _connectAndSync(GoogleCastDevice device) async {
    try {
      await widget.playbackManager.startCastingToDevice(device);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect Chromecast: $e')),
      );
    }
  }

  Future<void> _showConnectedActions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.cast),
                title: Text(
                  _castService.connectedDeviceName ?? 'Chromecast connected',
                ),
                subtitle: const Text('Audio is being cast from Ariami'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.cast),
                title: const Text('Disconnect'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await widget.playbackManager.stopCastingAndResumeLocal();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
