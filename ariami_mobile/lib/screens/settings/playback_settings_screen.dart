import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/audio/gapless_playback_service.dart';
import '../../services/audio/play_buttons_follow_playback_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../widgets/settings/settings_section.dart';
import '../../widgets/settings/settings_tile.dart';

/// How music plays, gathered in one place (as on desktop) rather than spread
/// across the main settings list. Streaming quality deliberately stays out
/// here: it is changed far more often than any of these.
class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  final GaplessPlaybackService _gaplessPlaybackService =
      GaplessPlaybackService();
  final PlayButtonsFollowPlaybackService _playButtonsService =
      PlayButtonsFollowPlaybackService();

  @override
  void initState() {
    super.initState();
    _gaplessPlaybackService.initialize();
    _playButtonsService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget toggle(
        {required bool value, required ValueChanged<bool> onChanged}) {
      return Switch(
        value: value,
        activeThumbColor: colorScheme.onPrimary,
        activeTrackColor: colorScheme.primary,
        inactiveThumbColor: colorScheme.onSurfaceVariant,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        onChanged: onChanged,
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Playback'),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.chevronLeft,
              size: 20, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ContentWidthLimiter(
        child: ListenableBuilder(
          listenable: Listenable.merge(
            [_gaplessPlaybackService, _playButtonsService],
          ),
          builder: (context, _) => ListView(
            padding: EdgeInsets.only(
              bottom: getMiniPlayerScrollBottomPadding(context),
            ),
            children: [
              SettingsSection(
                title: 'PLAYBACK',
                tiles: [
                  SettingsTile(
                    icon: Icons.playlist_play_rounded,
                    title: 'Gapless Playback',
                    subtitle: 'Play consecutive tracks without pauses',
                    onTap: () => _gaplessPlaybackService.setEnabled(
                      !_gaplessPlaybackService.isEnabled,
                    ),
                    trailing: toggle(
                      value: _gaplessPlaybackService.isEnabled,
                      onChanged: _gaplessPlaybackService.setEnabled,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.play_circle_outline_rounded,
                    title: 'Play Button Follows Playback',
                    subtitle: 'Show Pause on the album or playlist that is '
                        'playing, here or on another device',
                    onTap: () => _playButtonsService.setEnabled(
                      !_playButtonsService.isEnabled,
                    ),
                    trailing: toggle(
                      value: _playButtonsService.isEnabled,
                      onChanged: _playButtonsService.setEnabled,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.equalizer_rounded,
                    title: 'Equalizer',
                    subtitle: 'Presets and frequency bands',
                    onTap: () => Navigator.of(context).pushNamed('/equalizer'),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
