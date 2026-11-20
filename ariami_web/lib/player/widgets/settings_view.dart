import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connection_controller.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';
import 'settings/account_section.dart';
import 'settings/appearance_section.dart';
import 'settings/developer_section.dart';
import 'settings/general_section.dart';
import 'settings/hidden_items_section.dart';
import 'settings/playback_section.dart';
import 'settings/settings_rail.dart';
import 'settings/stats/listening_stats_section.dart';

/// Settings, organised by a navigation rail:
///
///  * App — general behaviour, appearance, playback, and the signed-in account.
///  * Server (server + player mode only) — the embedded server dashboard:
///    overview, activity, users, and configuration.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  SettingsSection _section = SettingsSection.general;
  PlayerNavigator? _nav;

  static SettingsSection _sectionFromId(String? id) => switch (id) {
        'general' => SettingsSection.general,
        'appearance' => SettingsSection.appearance,
        'playback' => SettingsSection.playback,
        'downloads' => SettingsSection.downloads,
        'listening-stats' || 'stats' => SettingsSection.listeningStats,
        'updates' => SettingsSection.updates,
        'account' => SettingsSection.account,
        'license' => SettingsSection.license,
        'hidden' || 'hidden-items' => SettingsSection.hiddenItems,
        'developer' => SettingsSection.developer,
        'server' || 'server-overview' => SettingsSection.serverOverview,
        'server-activity' => SettingsSection.serverActivity,
        'server-users' => SettingsSection.serverUsers,
        'server-config' => SettingsSection.serverConfig,
        _ => SettingsSection.general,
      };

  @override
  void initState() {
    super.initState();
    // Navigation can deep-link into a section, e.g.
    // `PlayerView(PlayerViewKind.settings, id: 'server')`.
    _section = _sectionFromId(context.read<PlayerNavigator>().current.id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = context.read<PlayerNavigator>();
    if (!identical(nav, _nav)) {
      _nav?.removeListener(_onNavChanged);
      _nav = nav..addListener(_onNavChanged);
    }
  }

  void _onNavChanged() {
    if (!mounted) return;
    final current = _nav?.current;
    if (current == null || current.kind != PlayerViewKind.settings) return;
    final next = _sectionFromId(current.id);
    if (_section != next) {
      setState(() => _section = next);
    }
  }

  @override
  void dispose() {
    _nav?.removeListener(_onNavChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLocalServer =
        context.select<ConnectionController, bool>((c) => c.isLocalServer);
    final host = maybeReadHost(context);
    final downloads = host?.downloads;
    final extra = host?.extraSettings;

    // Equalizer and gapless playback apply to both local and remote playback;
    // streaming quality is hidden inside the section when it is irrelevant.
    const showPlayback = true;
    // Downloads only make sense when playing from a remote server with a
    // downloads backend configured.
    final showDownloads = !isLocalServer && downloads != null;
    final showUpdates = extra?.supportsUpdates ?? false;
    final showLicense = extra?.buildLicenseSection(context) != null;
    final showServer = isLocalServer && extra != null;
    var section = _section;
    if (section.isServer && !showServer) {
      section = SettingsSection.general;
    }
    if (section == SettingsSection.downloads && !showDownloads) {
      section = SettingsSection.general;
    }
    if (section == SettingsSection.updates && !showUpdates) {
      section = SettingsSection.general;
    }
    if (section == SettingsSection.license && !showLicense) {
      section = SettingsSection.general;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 36, 40, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: PlayerTheme.display(64, color: context.colors.textPrimary),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 640;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: compact ? 52 : 190,
                      child: _buildRail(
                        section: section,
                        compact: compact,
                        showPlayback: showPlayback,
                        showDownloads: showDownloads,
                        showUpdates: showUpdates,
                        showLicense: showLicense,
                        showServer: showServer,
                      ),
                    ),
                    SizedBox(width: compact ? 16 : 40),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        reverseDuration: const Duration(milliseconds: 200),
                        transitionBuilder: Motion.fadeThrough,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            ...previous,
                            if (current != null) current,
                          ],
                        ),
                        // All server sections share one key: the embedded
                        // dashboard stays mounted (keeping its state and
                        // refresh timers) and only animates its inner tab.
                        child: KeyedSubtree(
                          key: ValueKey<String>(
                              section.isServer ? 'server' : section.name),
                          child: _buildContent(
                            context,
                            section,
                            downloads: downloads,
                            extra: extra,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRail({
    required SettingsSection section,
    required bool compact,
    required bool showPlayback,
    required bool showDownloads,
    required bool showUpdates,
    required bool showLicense,
    required bool showServer,
  }) {
    Widget item(SettingsSection s) => SettingsRailItem(
          section: s,
          selected: section == s,
          compact: compact,
          onTap: () => setState(() => _section = s),
        );

    return ListView(
      children: [
        // The groups only need naming when there is more than one.
        if (showServer) SettingsRailGroupLabel('This app', compact: compact),
        item(SettingsSection.general),
        item(SettingsSection.appearance),
        if (showPlayback) item(SettingsSection.playback),
        if (showDownloads) item(SettingsSection.downloads),
        item(SettingsSection.listeningStats),
        if (showUpdates) item(SettingsSection.updates),
        item(SettingsSection.account),
        if (showLicense) item(SettingsSection.license),
        item(SettingsSection.hiddenItems),
        item(SettingsSection.developer),
        if (showServer) ...[
          const SizedBox(height: 18),
          SettingsRailGroupLabel('Server', compact: compact),
          item(SettingsSection.serverOverview),
          item(SettingsSection.serverActivity),
          item(SettingsSection.serverUsers),
          item(SettingsSection.serverConfig),
        ],
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    SettingsSection section, {
    PlayerDownloadsBridge? downloads,
    PlayerExtraSettings? extra,
  }) {
    if (section.isServer) {
      return extra?.buildServerDashboard(context, section.name) ??
          const SizedBox.shrink();
    }
    if (section == SettingsSection.listeningStats) {
      return const ListeningStatsSection();
    }
    // The downloads section owns its scroll view: the queue can be long.
    if (section == SettingsSection.downloads) {
      return downloads?.buildSettingsSection() ?? const SizedBox.shrink();
    }
    final child = switch (section) {
      SettingsSection.general => const GeneralSection(),
      SettingsSection.appearance => const AppearanceSection(),
      SettingsSection.playback => const PlaybackSection(),
      SettingsSection.updates =>
        extra?.buildUpdatesSection(context) ?? const SizedBox.shrink(),
      SettingsSection.license =>
        extra?.buildLicenseSection(context) ?? const SizedBox.shrink(),
      SettingsSection.hiddenItems => const HiddenItemsSection(),
      SettingsSection.developer => const DeveloperSection(),
      _ => const AccountSection(),
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [child],
    );
  }
}
