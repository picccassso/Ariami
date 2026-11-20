import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/player_models.dart';
import '../../services/audio/gapless_playback_service.dart';
import '../../services/audio_controller.dart';
import '../../services/player_host.dart';
import '../equalizer_settings_panel.dart';
import 'settings_widgets.dart';

class PlaybackSection extends StatelessWidget {
  const PlaybackSection({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final gapless = context.watch<GaplessPlaybackService>();
    final hasDownloads = maybeReadHost(context)?.downloads != null;
    final discord = maybeWatchProvider<PlayerDiscordBridge?>(context) ??
        maybeWatchProvider<PlayerDiscordBridge>(context);
    return Column(
      children: [
        SettingsSectionCard(
          title: 'Gapless playback',
          subtitle: 'Preloads the next track so albums and playlists continue '
              'without silence between songs.',
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Play consecutive tracks without gaps',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: gapless.isEnabled,
                onChanged: gapless.setEnabled,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SettingsSectionCard(
          title: 'Play button follows playback',
          subtitle:
              'On the album, playlist or All Songs page that is currently '
              'playing, Play turns into Pause and Shuffle becomes a toggle for '
              'that queue — so you can see at a glance which one is playing. '
              'Every other page keeps starting its own collection.',
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Show what’s playing on Play and Shuffle',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: audio.playButtonsFollowPlayback,
                onChanged: audio.setPlayButtonsFollowPlayback,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SettingsSectionCard(
          title: 'Keep my queue when tapping a song',
          subtitle: 'Double-clicking a song plays it now, then carries on '
              'with your queue from where you left off. Play and Shuffle '
              'buttons still replace the queue. Option/Alt-click a song to do '
              'this once.',
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Play the song now, keep the queue after it',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: audio.keepQueueOnTap,
                onChanged: audio.setKeepQueueOnTap,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SettingsSectionCard(
          title: 'Stack Play next',
          subtitle: 'Play next normally puts a song straight after the one '
              'playing. With this on, it goes after the songs you already '
              'chose to play next, so they play in the order you picked them. '
              'Add to end of queue always adds after everything else.',
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Play next after earlier Play next picks',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: audio.stackPlayNext,
                onChanged: audio.setStackPlayNext,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const EqualizerSettingsPanel(),
        if (!audio.isLocalPlayback) ...[
          const SizedBox(height: 14),
          SettingsSectionCard(
            title: 'Streaming quality',
            subtitle: 'High streams the original file. Medium and Low are '
                'transcoded by the server to save bandwidth.',
            child: DesktopSegmentedControl<StreamQuality>(
              options: const [
                DesktopSegmentedOption(
                  value: StreamQuality.high,
                  label: 'High',
                  tooltip: 'Original file',
                ),
                DesktopSegmentedOption(
                  value: StreamQuality.medium,
                  label: 'Medium',
                  tooltip: 'Transcoded by the server',
                ),
                DesktopSegmentedOption(
                  value: StreamQuality.low,
                  label: 'Low',
                  tooltip: 'Transcoded by the server',
                ),
              ],
              selectedValue: audio.quality,
              onChanged: audio.setQuality,
              minSegmentWidth: 72,
            ),
          ),
          if (hasDownloads) ...[
            const SizedBox(height: 14),
            SettingsSectionCard(
              title: 'Play downloaded copies',
              subtitle: 'When a song is downloaded at the selected streaming '
                  'quality or better, play the local file instead of streaming. '
                  'Never lowers quality.',
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Prefer downloaded files while connected',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Switch(
                    value: audio.preferDownloadedWhenOnline,
                    onChanged: audio.setPreferDownloadedWhenOnline,
                  ),
                ],
              ),
            ),
          ],
        ],
        if (discord != null) ...[
          const SizedBox(height: 14),
          _DiscordPresenceCard(discord: discord),
        ],
      ],
    );
  }
}

/// Opt-in toggle for publishing the current track to Discord.
class _DiscordPresenceCard extends StatelessWidget {
  const _DiscordPresenceCard({required this.discord});

  final PlayerDiscordBridge discord;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: 'Discord status',
      subtitle: 'Shows the track you are playing on your Discord profile, '
          'where everyone in your servers can see it. Cover art is matched by '
          'sending the artist and album name to Apple’s public music '
          'catalogue — your library is never uploaded. Discord’s own Share my '
          'activity setting must also be enabled.',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Share what I’m listening to',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (discord.isEnabled) ...[
                  const SizedBox(height: 3),
                  Text(
                    discord.statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: discord.isError
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: discord.isEnabled,
            onChanged: (value) => discord.setEnabled(value),
          ),
        ],
      ),
    );
  }
}
