import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/debug_overlay_service.dart';
import 'settings_widgets.dart';

class DeveloperSection extends StatelessWidget {
  const DeveloperSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DebugOverlayService.instance,
      builder: (context, _) {
        final debug = DebugOverlayService.instance;
        return Column(
          children: [
            SettingsSectionCard(
              title: 'Playback debug overlay',
              subtitle: 'Shows a small live readout in the corner of the '
                  'player: what the current song is actually playing from '
                  '(file or stream, and at what bitrate), buffer health, '
                  'equalizer and connection details. Tap the readout to '
                  'expand it and copy a full report — handy when a song '
                  'sounds off and you want to tell whether it’s the file or '
                  'the stream.',
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Show playback debug info',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: debug.enabled,
                    onChanged: (value) =>
                        unawaited(debug.setEnabled(value)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
