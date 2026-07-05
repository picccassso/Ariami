import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/ariami_connect_controller.dart';
import '../../services/cast/chrome_cast_service.dart';
import '../../services/playback_manager.dart';
import '../common/mini_player_aware_bottom_sheet.dart';
import 'ariami_connect_button.dart';

enum _OutputPickerTarget { ariamiConnect, googleCast }

/// A single entry point for Ariami Connect and Google Cast.
///
/// When playback is remote, the active client name is shown beside the icon so
/// the player does not need a second connection-status row.
class PlayerOutputButton extends StatefulWidget {
  final PlaybackManager playbackManager;
  final bool showDeviceName;
  final Color? connectedColor;
  final Color? disconnectedColor;
  final double iconSize;

  const PlayerOutputButton({
    super.key,
    required this.playbackManager,
    this.showDeviceName = true,
    this.connectedColor,
    this.disconnectedColor,
    this.iconSize = 24,
  });

  @override
  State<PlayerOutputButton> createState() => _PlayerOutputButtonState();
}

class _PlayerOutputButtonState extends State<PlayerOutputButton> {
  final ChromeCastService _castService = ChromeCastService();
  final AriamiConnectController _connect = AriamiConnectController();

  @override
  void initState() {
    super.initState();
    _castService.initialize();
  }

  String? get _connectedDeviceName {
    if (_castService.isConnected) {
      return _castService.connectedDeviceName ?? 'Google Cast';
    }
    if (widget.playbackManager.isConnectRemoteActive) {
      return widget.playbackManager.connectRemoteDeviceName;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _castService,
        _connect,
        widget.playbackManager,
      ]),
      builder: (context, _) {
        final deviceName = _connectedDeviceName;
        final isConnected = deviceName != null;
        final colorScheme = Theme.of(context).colorScheme;
        final foregroundColor = isConnected
            ? widget.connectedColor ?? colorScheme.primary
            : widget.disconnectedColor ??
                colorScheme.onSurface.withValues(alpha: 0.9);

        return Semantics(
          button: true,
          label: deviceName == null
              ? 'Choose playback device'
              : 'Playing on $deviceName. Choose playback device',
          child: TextButton(
            key: const ValueKey('player-output-button'),
            onPressed: _showOutputPicker,
            style: TextButton.styleFrom(
              foregroundColor: foregroundColor,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isConnected ? Icons.devices_rounded : Icons.devices_outlined,
                  size: widget.iconSize,
                ),
                if (widget.showDeviceName && deviceName != null) ...[
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showOutputPicker() async {
    final target = await showAriamiSheet<_OutputPickerTarget>(
      context: context,
      header: const AriamiSheetHeader(
        title: 'Play on a device',
        subtitle: 'Choose how you want to listen',
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([_castService, _connect]),
        builder: (sheetContext, _) {
          final castConnected = _castService.isConnected;
          final castBusy = _castService.isConnecting ||
              widget.playbackManager.isCastTransitionInProgress;
          final canUseCast = _castService.canInteractWithCastButton(
            isConnected: castConnected,
            isBusy: castBusy,
          );

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('ariami-connect-option'),
                leading: const Icon(Icons.devices_rounded),
                title: const Text('Ariami Connect'),
                subtitle: Text(
                  widget.playbackManager.isConnectRemoteActive
                      ? widget.playbackManager.connectRemoteDeviceName ??
                          'Connected to an Ariami device'
                      : 'Listen on your signed-in Ariami devices',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(sheetContext).pop(
                  _OutputPickerTarget.ariamiConnect,
                ),
              ),
              const Divider(height: 1, indent: 72, endIndent: 16),
              ListTile(
                key: const ValueKey('google-cast-option'),
                enabled: canUseCast,
                leading: Icon(
                  castConnected
                      ? Icons.cast_connected_rounded
                      : LucideIcons.cast,
                ),
                title: const Text('Google Cast'),
                subtitle: Text(_castSubtitle(castConnected, castBusy)),
                trailing: castBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded),
                onTap: canUseCast
                    ? () => Navigator.of(sheetContext).pop(
                          _OutputPickerTarget.googleCast,
                        )
                    : null,
              ),
            ],
          );
        },
      ),
    );

    if (!mounted || target == null) return;
    switch (target) {
      case _OutputPickerTarget.ariamiConnect:
        await showAriamiConnectPicker(context);
      case _OutputPickerTarget.googleCast:
        await _onGoogleCastSelected();
    }
  }

  String _castSubtitle(bool isConnected, bool isBusy) {
    if (isConnected) {
      return _castService.connectedDeviceName ?? 'Connected';
    }
    if (isBusy) return 'Connecting…';
    if (!_castService.isSupportedPlatform) {
      return 'Not available on this device';
    }
    if (_castService.isBlockedByOffline) {
      return 'Unavailable while offline';
    }
    return 'Cast to speakers and displays';
  }

  Future<void> _onGoogleCastSelected() async {
    if (_castService.isConnected) {
      await _showConnectedCastActions();
      return;
    }
    await _showCastDevicePicker();
  }

  Future<void> _showCastDevicePicker() async {
    await _castService.startDiscovery();
    if (!mounted) return;

    await showAriamiSheet<void>(
      context: context,
      header: const AriamiSheetHeader(
        title: 'Google Cast',
        subtitle: 'Pick a device on your network',
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
                  Expanded(child: Text('Searching for Google Cast devices…')),
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
      // The picker can be reopened to retry a failed Cast connection.
    }
  }

  Future<void> _showConnectedCastActions() async {
    final deviceName = _castService.connectedDeviceName ?? 'Google Cast';
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
